import Foundation
import os

/// Main entry point for HotReload functionality.
///
/// Configure hot reload in your app by calling `HotReload.configure()` early
/// in your app's lifecycle, then use `.enableInjection()` on your root view.
public enum HotReload {
    /// Protocol version for CLI/Kit compatibility checks
    public static let protocolVersion = 1

    #if DEBUG
    private static let logger = Logger(subsystem: "com.hotreload", category: "hotreload")

    /// Whether hot reload has been configured
    public private(set) static var isConfigured = false

    /// Configure the hot reload system.
    ///
    /// Starts the TCP injection server and wires the reload pipeline.
    ///
    /// - Parameter port: TCP port for the injection server (default: 8899)
    public static func configure(port: UInt16 = 8899) {
        guard !isConfigured else { return }

        // Set up the reload handler
        HotReloadCallbacks.shared.onReload = { dylibName, dylibURL in
            await handleReload(dylibName: dylibName, dylibURL: dylibURL)
        }

        HotReloadCallbacks.shared.onPing = {
            return "pong:v\(protocolVersion)"
        }

        do {
            try HotReloadServer.shared.start(port: port)
            isConfigured = true
            logger.info("HotReload configured on port \(port)")
        } catch {
            logger.error("Failed to configure HotReload: \(error.localizedDescription)")
        }
    }

    /// Manually trigger a reload (useful for debugging)
    public static func triggerReload() {
        Task { @MainActor in
            InjectionState.shared.advance()
            NotificationCenter.default.post(name: .hotReloadDidInject, object: nil)
        }
    }

    // MARK: - Internal

    fileprivate static func handleReload(dylibName: String, dylibURL: String) async {
        logger.info("Injection requested: \(dylibName) from \(dylibURL)")

        do {
            let data = try await InjectionClient.shared.fetchDylib(urlString: dylibURL)
            let success = await InjectionLoader.shared.inject(data: data, dylibName: dylibName)
            if success {
                logger.info("Injected: \(dylibName)")
            } else {
                logger.error("Injection failed: \(dylibName)")
            }
        } catch {
            logger.error("Fetch failed: \(error.localizedDescription)")
        }
    }
    #else
    public private(set) static var isConfigured = false

    public static func configure(port: UInt16 = 8899) {
        // no-op in Release
    }

    public static func triggerReload() {
        // no-op in Release
    }
    #endif
}
