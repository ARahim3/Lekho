import Cocoa
import InputMethodKit

// Connection name MUST match Info.plist's InputMethodConnectionName
let kConnectionName = "com.lekho.inputmethod.Lekho_Connection"

// IMKServer must be a global to stay alive for the process lifetime
var server: IMKServer!

// Build identifier — check Console.app for "Lekho" to verify which build is running
let lekhoBuildId = "build-20260922a"
NSLog("Lekho: starting %@", lekhoBuildId)

// Install a minimal main menu so the welcome window honors standard Mac
// keyboard shortcuts (Cmd+W, Cmd+Q, Cmd+C/V/X/A) when it is the key window.
// Without an NSApp.mainMenu, an LSUIElement app has no key-equivalents to
// dispatch, so these shortcuts are silently ignored.
//
// Cmd+Q is intentionally rebound to performClose: instead of terminate:.
// This process is the IME service — terminating it interrupts typing system-
// wide. Closing the window is what users actually want here.
func installMainMenu() {
    let mainMenu = NSMenu()

    // App menu (title is the leftmost item label macOS shows in the menu bar)
    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)
    let appMenu = NSMenu(title: "Lekho")
    appMenu.addItem(NSMenuItem(
        title: "Close Window",
        action: #selector(NSWindow.performClose(_:)),
        keyEquivalent: "w"))
    appMenu.addItem(NSMenuItem(
        title: "Close Window",
        action: #selector(NSWindow.performClose(_:)),
        keyEquivalent: "q"))
    appMenu.addItem(NSMenuItem(
        title: "Hide Lekho",
        action: #selector(NSApplication.hide(_:)),
        keyEquivalent: "h"))
    appMenuItem.submenu = appMenu

    // Edit menu — needed for Cmd+C/V/X/A in the alert/text fields the welcome
    // window opens (e.g. update-check error messages).
    let editMenuItem = NSMenuItem()
    mainMenu.addItem(editMenuItem)
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
    let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    editMenu.addItem(redo)
    editMenu.addItem(NSMenuItem.separator())
    editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
    editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
    editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
    editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a"))
    editMenuItem.submenu = editMenu

    NSApplication.shared.mainMenu = mainMenu
}

installMainMenu()

// Register menu bar icon as template BEFORE IMKServer loads it —
// PDF template icon: macOS auto-inverts for dark menu bars + Globe key overlay
if let iconPath = Bundle.main.path(forResource: "iconTemplate", ofType: "pdf"),
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
