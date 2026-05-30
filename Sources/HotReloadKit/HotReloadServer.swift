#if DEBUG
import Foundation
import Network
import os

public final class HotReloadCallbacks: @unchecked Sendable {
    public static let shared = HotReloadCallbacks()

    public var onReload: ((_ dylibName: String, _ dylibURL: String) async -> Void)?
    public var onPing: (() -> String)?

    private init() {}
}

private final class ResultBox: @unchecked Sendable {
    var value: InjectionResponse = .error("timeout")
}

public final class HotReloadServer: @unchecked Sendable {
    public static let shared = HotReloadServer()

    private var serverFd: Int32 = -1
    private var serverSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.hotreload.server")
    private static let injectionQueue = DispatchQueue(label: "com.hotreload.injection")
    public private(set) var boundPort: UInt16?

    private init() {}

    public func start(port: UInt16 = 8899) throws {
        serverFd = Darwin.socket(AF_INET6, SOCK_STREAM, 0)
        guard serverFd >= 0 else { throw NSError(domain: "HotReload", code: 1, userInfo: [NSLocalizedDescriptionKey: "socket() failed"]) }

        var yes: Int32 = 1
        setsockopt(serverFd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var noV6Only: Int32 = 0
        setsockopt(serverFd, IPPROTO_IPV6, IPV6_V6ONLY, &noV6Only, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in6()
        addr.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        addr.sin6_family = sa_family_t(AF_INET6)
        addr.sin6_port = port.bigEndian
        addr.sin6_addr = in6addr_any

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(serverFd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) }
        }
        guard bindResult == 0 else { throw NSError(domain: "HotReload", code: 2, userInfo: [NSLocalizedDescriptionKey: "bind() failed: \(errno)"]) }

        guard Darwin.listen(serverFd, 5) == 0 else { throw NSError(domain: "HotReload", code: 3, userInfo: [NSLocalizedDescriptionKey: "listen() failed"]) }

        let source = DispatchSource.makeReadSource(fileDescriptor: serverFd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptConnection() }
        source.resume()
        serverSource = source
        boundPort = port
    }

    public func stop() {
        serverSource?.cancel()
        if serverFd >= 0 { Darwin.close(serverFd); serverFd = -1 }
    }

    private func acceptConnection() {
        var clientAddr = sockaddr_in6()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in6>.size)
        let clientFd = withUnsafeMutablePointer(to: &clientAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.accept(serverFd, $0, &addrLen) }
        }
        guard clientFd >= 0 else { return }

        queue.async { Self.handleClient(fd: clientFd) }
    }

    private static func handleClient(fd: Int32) {
        defer { Darwin.close(fd) }

        guard let headerData = readExact(fd: fd, count: 4) else { return }
        let length = Int(UInt32(bigEndian: headerData.withUnsafeBytes { $0.load(as: UInt32.self) }))
        guard length > 0, length < 1_000_000 else { return }

        guard let payload = readExact(fd: fd, count: length) else { return }

        let response = processCommand(payload)

        guard let json = try? JSONEncoder().encode(response) else { return }
        var respLen = UInt32(json.count).bigEndian
        var packet = Data()
        withUnsafeBytes(of: &respLen) { packet.append(contentsOf: $0) }
        packet.append(json)

        packet.withUnsafeBytes { ptr in
            _ = Darwin.send(fd, ptr.baseAddress!, ptr.count, 0)
        }
    }

    private static func readExact(fd: Int32, count: Int) -> Data? {
        var buffer = Data(count: count)
        var offset = 0
        while offset < count {
            let n = buffer.withUnsafeMutableBytes { ptr in
                Darwin.recv(fd, ptr.baseAddress! + offset, count - offset, 0)
            }
            if n <= 0 { return nil }
            offset += n
        }
        return buffer
    }

    private static func processCommand(_ data: Data) -> InjectionResponse {
        guard let command = try? JSONDecoder().decode(InjectionCommand.self, from: data) else {
            return .error("decode failed")
        }

        let callbacks = HotReloadCallbacks.shared

        switch command.command {
        case "reload":
            guard let dylibName = command.dylib_name, let dylibURL = command.dylib_url else {
                return .error("missing dylib_name or dylib_url")
            }
            guard let onReload = callbacks.onReload else {
                return .error("no reload handler")
            }

            let box = ResultBox()
            let semaphore = DispatchSemaphore(value: 0)

            injectionQueue.async {
                let group = DispatchGroup()
                group.enter()
                Task {
                    await onReload(dylibName, dylibURL)
                    box.value = .ok("injected")
                    group.leave()
                }
                group.wait()
                semaphore.signal()
            }

            let timeout = semaphore.wait(timeout: .now() + 10)
            if timeout == .timedOut {
                return .error("injection timeout")
            }
            return box.value

        case "ping":
            let msg = callbacks.onPing?() ?? "pong"
            return .ok(msg)

        default:
            return .error("unknown command")
        }
    }
}
#endif
