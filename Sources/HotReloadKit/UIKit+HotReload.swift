#if DEBUG
import UIKit
import ObjectiveC

// MARK: - UIKit Injection Support

extension UIViewController {
    /// Enable injection for this view controller.
    /// On injection, the view controller's view will be reloaded.
    public func enableInjection() {
        NotificationCenter.default.addObserver(
            forName: .hotReloadDidInject,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleInjection()
        }
    }

    @objc fileprivate func _hotreload_viewDidLoad() {
        _hotreload_viewDidLoad()  // calls original (swizzled)
        enableInjection()
    }

    private func handleInjection() {
        guard isViewLoaded else { return }
        loadView()
        viewDidLoad()
    }
}

// MARK: - UIApplication Delegate Helper

extension UIApplication {
    /// Configure hot reload for UIKit apps.
    /// Automatically enables injection on ALL view controllers via swizzling.
    ///
    /// ```swift
    /// func application(_ application: UIApplication, didFinishLaunchingWithOptions ...) -> Bool {
    ///     UIApplication.enableHotReload()
    ///     return true
    /// }
    /// ```
    public static func enableHotReload(port: UInt16 = 8899) {
        HotReload.configure(port: port)
        swizzleViewDidLoad()
    }

    private static func swizzleViewDidLoad() {
        let original = class_getInstanceMethod(UIViewController.self, #selector(UIViewController.viewDidLoad))!
        let swizzled = class_getInstanceMethod(UIViewController.self, #selector(UIViewController._hotreload_viewDidLoad))!
        method_exchangeImplementations(original, swizzled)
    }
}

#else
import UIKit

extension UIApplication {
    /// No-op in Release builds.
    @inline(__always)
    public static func enableHotReload(port: UInt16 = 8899) {
        // no-op
    }
}

#endif
