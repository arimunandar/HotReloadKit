import SwiftUI

#if DEBUG
// MARK: - Injection Observer

/// Shared observer that manages injection notifications without adding multiple observers.
private final class InjectionObserver: ObservableObject {
    static let shared = InjectionObserver()

    @Published var generation: UInt64 = InjectionState.shared.generation

    private var observer: NSObjectProtocol?
    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .hotReloadDidInject,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.generation = InjectionState.shared.generation
        }
    }

    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

// MARK: - ObserveInjection Property Wrapper

/// Optional property wrapper that causes SwiftUI views to refresh on injection.
///
/// Most views do NOT need this -- `.enableInjection()` on your root view is sufficient.
/// Use `@ObserveInjection` only if a specific deeply-nested view does not refresh.
///
/// Usage:
/// ```swift
/// struct StubbornView: View {
///     @ObserveInjection var redraw
///     var body: some View {
///         Text("I need extra help refreshing")
///     }
/// }
/// ```
@propertyWrapper
public struct ObserveInjection: DynamicProperty {
    @ObservedObject private var observer = InjectionObserver.shared

    public init() {}

    public var wrappedValue: some Any {
        observer.generation
    }

    public var projectedValue: Self { self }
}

// MARK: - EnableInjection View Modifier

/// A view modifier that forces view re-evaluation on injection.
private struct InjectionModifier: ViewModifier {
    @State private var generation: UInt64 = InjectionState.shared.generation

    func body(content: Content) -> some View {
        content
            .id(generation)
            .onReceive(NotificationCenter.default.publisher(for: .hotReloadDidInject)) { _ in
                generation = InjectionState.shared.generation
            }
    }
}

extension View {
    /// Enables hot reload injection for this view hierarchy.
    /// Place on the root view of your app:
    /// ```swift
    /// @main
    /// struct MyApp: App {
    ///     var body: some Scene {
    ///         WindowGroup {
    ///             ContentView()
    ///                 .enableInjection()
    ///         }
    ///     }
    /// }
    /// ```
    public func enableInjection() -> some View {
        modifier(InjectionModifier())
    }
}

#else

// MARK: - Release stubs

@propertyWrapper
public struct ObserveInjection: DynamicProperty {
    public init() {}

    public var wrappedValue: some Any {
        UInt64(0)
    }

    public var projectedValue: Self { self }
}

extension View {
    /// No-op in Release builds.
    @inline(__always)
    public func enableInjection() -> some View {
        self
    }
}

#endif
