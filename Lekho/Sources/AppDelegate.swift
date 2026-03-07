import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only show welcome window on first-ever install (no user data yet).
        // For subsequent opens, applicationShouldHandleReopen handles it.
        // install.sh relaunches the app after installing, so user clicks
        // always go through applicationShouldHandleReopen.
        let userDir = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Lekho")

        if !FileManager.default.fileExists(atPath: userDir.path) {
            WelcomeWindowController.shared.showWindow()
        }
    }

    // Called when user clicks the app icon while it's already running
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        WelcomeWindowController.shared.showWindow()
        return true
    }
}
