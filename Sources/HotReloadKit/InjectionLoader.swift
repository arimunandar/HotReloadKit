#if DEBUG
import Foundation
import MachO
import os

public actor InjectionLoader {
    public static let shared = InjectionLoader()

    private let logger = Logger(subsystem: "com.hotreload", category: "loader")
    private var loadedModules: Set<String> = []
    private static let patchLock: UnsafeMutablePointer<os_unfair_lock> = {
        let lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
        return lock
    }()

    private init() {}

    public func inject(data: Data, dylibName: String) -> Bool {
        let tempDir = FileManager.default.temporaryDirectory
        let dylibPath = tempDir.appendingPathComponent(dylibName)

        do {
            try data.write(to: dylibPath)
        } catch {
            logger.notice("[HotReload] Failed to write dylib to \(dylibPath.path): \(error.localizedDescription)")
            return false
        }

        return loadDylib(path: dylibPath.path, dylibName: dylibName)
    }

    public func loadDylib(path: String, dylibName: String) -> Bool {
        logger.notice("[HotReload] Loading dylib: \(path)")

        guard let handle = dlopen(path, RTLD_LAZY) else {
            let dlErr = String(cString: dlerror())
            logger.notice("[HotReload] dlopen FAILED: \(dlErr)")
            return false
        }

        logger.notice("[HotReload] dlopen succeeded for \(dylibName)")
        loadedModules.insert(dylibName)

        os_unfair_lock_lock(Self.patchLock)
        let patchCount = patchDynamicReplacements(dylibHandle: handle)
        logger.notice("[HotReload] Patched \(patchCount) dynamic replacement(s)")
        os_unfair_lock_unlock(Self.patchLock)

        DispatchQueue.main.async {
            InjectionState.shared.advance()
            NotificationCenter.default.post(name: .hotReloadDidInject, object: nil)
        }
        logger.notice("[HotReload] Scheduled hotReloadDidInject notification")

        return true
    }

    public func isLoaded(dylibName: String) -> Bool {
        loadedModules.contains(dylibName)
    }

    // MARK: - Dynamic Replacement Patching

    /// Scan the main binary for Swift dynamic replacement variables (TX symbols)
    /// and patch them to point to new implementations from the loaded dylib.
    private static let excludedTypes = [
        "InjectionLoader", "InjectionClient", "InjectionState",
        "InjectionCommand", "InjectionResponse", "InjectionError",
        "HotReloadServer", "HotReloadCallbacks", "HotReload",
        "ObserveInjection", "InjectionObserver", "InjectionModifier",
        "os_unfair_lock", "TodoStore",
    ]

    private func patchDynamicReplacements(dylibHandle: UnsafeMutableRawPointer) -> Int {
        var patchCount = 0
        var txSymbolCount = 0
        var dlsymFailCount = 0

        // Scan ALL loaded images (Xcode 26+ puts app code in a debug dylib, not image 0)
        let imageCount = _dyld_image_count()
        for imageIndex in 0..<imageCount {
            guard let header = _dyld_get_image_header(imageIndex) else { continue }
            let slide = _dyld_get_image_vmaddr_slide(imageIndex)

            enumerateSymbols(header: header, slide: slide) { name, address in
            guard name.hasSuffix("TX") else { return }

            for excluded in Self.excludedTypes {
                if name.contains(excluded) { return }
            }

            txSymbolCount += 1

            var funcName = String(name.dropLast(2))
            if funcName.hasPrefix("_") {
                funcName = String(funcName.dropFirst())
            }

            guard let replacement = dlsym(dylibHandle, funcName) else {
                dlsymFailCount += 1
                return
            }

            let txPointer = address.assumingMemoryBound(to: UnsafeMutableRawPointer?.self)
            txPointer.pointee = replacement
            patchCount += 1
            logger.notice("[HotReload] Patched TX: \(funcName)")
            }
        }

        logger.notice("[HotReload] TX summary: \(txSymbolCount) found, \(patchCount) patched, \(dlsymFailCount) dlsym misses (\(imageCount) images scanned)")
        return patchCount
    }

    /// Walk the Mach-O symbol table of an image, calling the handler for each local symbol.
    private func enumerateSymbols(
        header: UnsafePointer<mach_header>,
        slide: Int,
        handler: (String, UnsafeMutableRawPointer) -> Void
    ) {
        let headerPtr = UnsafeRawPointer(header)
        var cursor = headerPtr + (header.pointee.magic == MH_MAGIC_64
            ? MemoryLayout<mach_header_64>.size
            : MemoryLayout<mach_header>.size)

        var symtabCmd: UnsafePointer<symtab_command>?

        for _ in 0..<header.pointee.ncmds {
            let cmd = cursor.assumingMemoryBound(to: load_command.self)
            if cmd.pointee.cmd == LC_SYMTAB {
                symtabCmd = cursor.assumingMemoryBound(to: symtab_command.self)
                break
            }
            cursor += Int(cmd.pointee.cmdsize)
        }

        guard let symtab = symtabCmd else { return }

        let linkeditBase = findLinkeditBase(header: header, slide: slide)
        guard let base = linkeditBase else { return }

        let nlistArray = (base + Int(symtab.pointee.symoff))
            .assumingMemoryBound(to: nlist_64.self)
        let stringTable = (base + Int(symtab.pointee.stroff))
            .assumingMemoryBound(to: CChar.self)

        for i in 0..<Int(symtab.pointee.nsyms) {
            let nlist = nlistArray[i]

            // Skip undefined, debug, and absolute symbols
            let type = nlist.n_type & UInt8(N_TYPE)
            guard type == UInt8(N_SECT) else { continue }

            let nameOffset = Int(nlist.n_un.n_strx)
            let name = String(cString: stringTable + nameOffset)

            // Only process Swift dynamic replacement variables
            guard name.hasPrefix("_$s"), name.hasSuffix("TX") else { continue }

            let address = UnsafeMutableRawPointer(
                bitPattern: Int(nlist.n_value) + slide
            )
            guard let addr = address else { continue }

            handler(name, addr)
        }
    }

    /// Find the __LINKEDIT base by computing: slide + vmaddr - fileoff
    private func findLinkeditBase(
        header: UnsafePointer<mach_header>,
        slide: Int
    ) -> UnsafeRawPointer? {
        let headerPtr = UnsafeRawPointer(header)
        var cursor = headerPtr + (header.pointee.magic == MH_MAGIC_64
            ? MemoryLayout<mach_header_64>.size
            : MemoryLayout<mach_header>.size)

        for _ in 0..<header.pointee.ncmds {
            let cmd = cursor.assumingMemoryBound(to: load_command.self)
            if cmd.pointee.cmd == LC_SEGMENT_64 {
                let seg = cursor.assumingMemoryBound(to: segment_command_64.self)
                let segName = withUnsafePointer(to: seg.pointee.segname) { ptr in
                    String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
                }
                if segName == "__LINKEDIT" {
                    return UnsafeRawPointer(bitPattern: slide + Int(seg.pointee.vmaddr) - Int(seg.pointee.fileoff))
                }
            }
            cursor += Int(cmd.pointee.cmdsize)
        }
        return nil
    }
}
#endif
