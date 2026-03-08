import Cocoa
import InputMethodKit

// Connection name MUST match Info.plist's InputMethodConnectionName
let kConnectionName = "com.lekho.inputmethod.Lekho_Connection"

// IMKServer must be a global to stay alive for the process lifetime
var server: IMKServer!

// Build identifier — check Console.app for "Lekho" to verify which build is running
let lekhoBuildId = "build-20260309a"
NSLog("Lekho: starting %@", lekhoBuildId)

// Register menu bar icon as template BEFORE IMKServer loads it —
// macOS auto-inverts template images for dark menu bars (black ↔ white)
if let iconPath = Bundle.main.path(forResource: "iconTemplate", ofType: "tiff"),
   let icon = NSImage(contentsOfFile: iconPath) {
    icon.isTemplate = true
    icon.setName("iconTemplate")
}

autoreleasepool {
    server = IMKServer(name: kConnectionName,
                       bundleIdentifier: Bundle.main.bundleIdentifier!)

    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate

    // Keep a strong reference so ARC doesn't release it
    withExtendedLifetime(delegate) {
        NSApplication.shared.run()
    }
}
