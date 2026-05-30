# HotReloadKit

Swift package that receives and applies hot-reloaded code from the [hotreload](https://github.com/AriMunanworked/hotreload) CLI.

## Installation

Add via Swift Package Manager:

```
https://github.com/AriMunandar/HotReloadKit.git
```

HotReloadKit is safe to keep as a permanent dependency. All functional code is wrapped in `#if DEBUG` -- Release builds compile to no-ops with zero runtime cost.

## SwiftUI Setup

```swift
import HotReloadKit

@main
struct MyApp: App {
    init() {
        HotReload.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .enableInjection()
        }
    }
}
```

That's it. Every view in the hierarchy under `.enableInjection()` will refresh on injection.

If a specific deeply-nested view does not refresh, add `@ObserveInjection` as an escape hatch:

```swift
struct StubbornView: View {
    @ObserveInjection var redraw
    var body: some View {
        Text("Now I refresh too")
    }
}
```

## UIKit Setup

```swift
func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
) -> Bool {
    UIApplication.enableHotReload()
    return true
}
```

This calls `HotReload.configure()` and swizzles `viewDidLoad` so all view controllers automatically reload on injection.

## Release Builds

All hot reload code is compiled out in Release via `#if DEBUG`. The public API surface (`HotReload.configure()`, `.enableInjection()`, `@ObserveInjection`, `UIApplication.enableHotReload()`) still exists but does nothing, so you never need conditional imports.

## CLI

This package is the client side only. You need the [hotreload](https://github.com/AriMunandar/hotreload) CLI to watch for file changes, recompile, and push dylibs to the app.
