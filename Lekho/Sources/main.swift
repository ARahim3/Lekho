import Cocoa
import InputMethodKit

// Connection name MUST match Info.plist's InputMethodConnectionName
let kConnectionName = "com.lekho.inputmethod.Lekho_Connection"

// IMKServer must be a global to stay alive for the process lifetime
var server: IMKServer!

// Build identifier — check Console.app for "Lekho" to verify which build is running
let lekhoBuildId = "build-20260506b"
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

// Bundled fonts (Resources/fonts, recursive) are registered for this process by
// Info.plist's ATSApplicationFontsPath before main runs — no code needed.

// MARK: - System-wide font install

/// Version of a font: head.fontRevision, or the name-table version string when
/// that is higher (July Bold-Italic bumps one but not the other).
private func fontVersion(_ font: CTFont) -> Double {
    var version = 0.0
    if let head = CTFontCopyTable(font, CTFontTableTag(kCTFontTableHead), []) as Data?, head.count >= 8 {
        let fixed = head[4..<8].reduce(0) { ($0 << 8) | UInt32($1) }  // 16.16 big-endian
        version = Double(Int32(bitPattern: fixed)) / 65536
    }
    if let s = CTFontCopyName(font, kCTFontVersionNameKey) as String?,
       let r = s.range(of: #"\d+\.\d+"#, options: .regularExpression),
       let named = Double(s[r]) {
        version = max(version, named)
    }
    return version
}

/// Load a font file without registering it.
private func fontAtURL(_ url: URL) -> CTFont? {
    guard let descs = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
          let desc = descs.first else { return nil }
    return CTFontCreateWithFontDescriptor(desc, 0, nil)
}

/// Copy the bundled fonts into ~/Library/Fonts so every app can use them. A copy
/// the user already has is replaced only when the bundled one is newer. Copies in
/// /Library/Fonts need admin rights to touch, so an older one there is shadowed by
/// the user-domain copy instead (user fonts take precedence on macOS).
func installBundledFontsSystemWide() {
    let fm = FileManager.default
    guard let bundleFonts = Bundle.main.url(forResource: "fonts", withExtension: nil),
          let files = fm.enumerator(at: bundleFonts, includingPropertiesForKeys: nil) else { return }
    let userFonts = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Fonts")
    try? fm.createDirectory(at: userFonts, withIntermediateDirectories: true)

    for case let src as URL in files where ["ttf", "otf"].contains(src.pathExtension.lowercased()) {
        guard let font = fontAtURL(src) else { continue }
        let name = CTFontCopyPostScriptName(font) as String
        let bundledVersion = fontVersion(font)

        // Every installed copy of this face outside our bundle.
        let query = CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: name] as CFDictionary)
        let matches = CTFontDescriptorCreateMatchingFontDescriptors(
            query, NSSet(array: [kCTFontNameAttribute]) as CFSet) as? [CTFontDescriptor] ?? []
        let installed = matches
            .compactMap { CTFontDescriptorCopyAttribute($0, kCTFontURLAttribute) as? URL }
            .filter { !$0.path.hasPrefix(bundleFonts.path) }
            .compactMap { url in fontAtURL(url).map { (url: url, version: fontVersion($0)) } }
        if installed.contains(where: { $0.version >= bundledVersion }) { continue }

        // Overwrite the user's older copy in place; otherwise add one.
        let dest = installed.first { $0.url.path.hasPrefix(userFonts.path) }?.url
            ?? userFonts.appendingPathComponent(src.lastPathComponent)
        do {
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: src, to: dest)
            NSLog("Lekho: installed font %@ %.3f -> %@", name, bundledVersion, dest.path)
        } catch {
            NSLog("Lekho: could not install font %@: %@", name, error.localizedDescription)
        }
    }
}

// Off the main thread so IMKServer startup isn't delayed; CoreText is thread-safe here.
DispatchQueue.global(qos: .utility).async { installBundledFontsSystemWide() }

extension NSFont {
    /// `base` with the bundled July font as its Bangla fallback. One font object:
    /// Latin/digits/emoji keep the system font, Bengali (which SF doesn't cover)
    /// falls through to July — July-Bold when `base` is semibold or heavier.
    static func withBangla(_ base: NSFont) -> NSFont {
        let traits = base.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        let weight = traits?[.weight] as? CGFloat ?? 0
        let face = weight >= NSFont.Weight.semibold.rawValue ? "July-Bold" : "July"
        let desc = base.fontDescriptor.addingAttributes(
            [.cascadeList: [NSFontDescriptor(name: face, size: base.pointSize)]])
        return NSFont(descriptor: desc, size: base.pointSize) ?? base
    }
}

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
