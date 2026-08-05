import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            menuBar = MenuBarController()
        }
    }

    /// zbar has no windows, so "opening" an already-running instance should do
    /// the only thing opening zbar could mean: show the ask box.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        MainActor.assumeIsolated {
            menuBar?.showQuickAsk()
        }
        return false
    }
}
