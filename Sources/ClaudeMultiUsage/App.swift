import SwiftUI
import AppKit

@main
struct ClaudeMultiUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: AppModel.shared)
        } label: {
            MenuBarLabel(model: AppModel.shared)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu-bar only, no dock icon
        AppModel.shared.start()
    }
}

/// AppKit-managed window for the OAuth code entry. Kept out of the SwiftUI
/// scene graph so nothing pops up on launch; shown only on demand.
@MainActor
final class AddAccountWindowController {
    static let shared = AddAccountWindowController()
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let hosting = NSHostingController(rootView: AddAccountView(model: model))
            let w = NSWindow(contentViewController: hosting)
            w.title = L("add.title")
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }
}
