import Foundation

// MARK: - Injection Command

/// Command sent from the Rust CLI to the iOS app via TCP (length-prefixed JSON)
public struct InjectionCommand: Codable, Sendable {
    /// "reload" or "ping"
    public let command: String
    /// Name of the dylib file (only for reload)
    public let dylib_name: String?
    /// URL to fetch the dylib from (only for reload)
    public let dylib_url: String?

    public init(command: String, dylibName: String? = nil, dylibURL: String? = nil) {
        self.command = command
        self.dylib_name = dylibName
        self.dylib_url = dylibURL
    }
}

// MARK: - Injection Response

/// Response sent back to the CLI
public struct InjectionResponse: Codable, Sendable {
    /// "ok" or "error"
    public let status: String
    /// Human-readable message
    public let message: String

    public init(status: String, message: String) {
        self.status = status
        self.message = message
    }

    public static func ok(_ message: String) -> InjectionResponse {
        InjectionResponse(status: "ok", message: message)
    }

    public static func error(_ message: String) -> InjectionResponse {
        InjectionResponse(status: "error", message: message)
    }
}

// MARK: - Injection State

#if DEBUG
/// Thread-safe shared state for injection counters
public final class InjectionState: @unchecked Sendable {
    public static let shared = InjectionState()

    /// Monotonically increasing counter, incremented on each successful injection
    private var _counter: UInt64 = 0
    private var lock = os_unfair_lock()

    private init() {}

    /// The current injection generation (thread-safe read)
    public var generation: UInt64 {
        lock.withLock { _counter }
    }

    /// Increment and return the new generation
    @discardableResult
    public func advance() -> UInt64 {
        lock.withLock {
            _counter += 1
            return _counter
        }
    }
}

// MARK: - os_unfair_lock helper

private extension os_unfair_lock {
    mutating func withLock<T>(_ body: () throws -> T) rethrows -> T {
        os_unfair_lock_lock(&self)
        defer { os_unfair_lock_unlock(&self) }
        return try body()
    }
}

// MARK: - Notification

extension Notification.Name {
    public static let hotReloadDidInject = Notification.Name("com.hotreload.didInject")
}
#else
/// Minimal stub for Release builds -- provides the same API surface with no runtime cost.
public final class InjectionState: Sendable {
    public static let shared = InjectionState()
    private init() {}

    public var generation: UInt64 { 0 }

    @discardableResult
    public func advance() -> UInt64 { 0 }
}
#endif
