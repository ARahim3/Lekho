import Cocoa

/// User-facing appearance settings for the suggestion popup: which installed
/// font draws the Bangla text, and at what size.
///
/// Only the popup (and the welcome window's layout chart) is affected. The words
/// the user commits are rendered by the host app in whatever font it uses —
/// an input method has no say in that.
enum LekhoAppearance {
    /// UserDefaults string: font family for Bangla glyphs in the popup.
    /// Absent or empty = macOS default (Kohinoor Bangla via system fallback).
    static let fontFamilyKey = "LekhoCandidateFontFamily"
    /// UserDefaults double: point size of candidate rows. Absent/0 = `defaultFontSize`.
    static let fontSizeKey = "LekhoCandidateFontSize"

    static let defaultFontSize: CGFloat = 16
    static let fontSizes: [CGFloat] = [13, 14, 15, 16, 17, 18, 20, 22, 24]

    static func currentFontFamily() -> String? {
        let raw = UserDefaults.standard.string(forKey: fontFamilyKey) ?? ""
        return raw.isEmpty ? nil : raw
    }

    static func currentFontSize() -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: fontSizeKey)
        return stored > 0 ? CGFloat(stored) : defaultFontSize
    }

    static func setFontFamily(_ family: String?) {
        UserDefaults.standard.set(family ?? "", forKey: fontFamilyKey)
        NotificationCenter.default.post(name: .lekhoAppearanceChanged, object: nil)
    }

    static func setFontSize(_ size: CGFloat) {
        UserDefaults.standard.set(Double(size), forKey: fontSizeKey)
        NotificationCenter.default.post(name: .lekhoAppearanceChanged, object: nil)
    }

    // MARK: Fonts

    private static var cachedFont: NSFont?
    private static var cachedKey = ""

    /// Font for candidate rows, cached until the settings change. Cheap enough
    /// to call from `draw(_:)` on every keystroke.
    static func candidateFont() -> NSFont {
        let family = currentFontFamily()
        let size = currentFontSize()
        let key = "\(family ?? "")|\(size)"
        if let font = cachedFont, cachedKey == key { return font }
        let font = makeFont(family: family, size: size)
        cachedFont = font
        cachedKey = key
        return font
    }

    /// The system font stays the base so Latin text, digits and emoji look
    /// native; the chosen family is put at the top of the cascade list, so it
    /// only takes over for the glyphs the system font lacks — the Bangla ones.
    static func makeFont(family: String?, size: CGFloat) -> NSFont {
        let system = NSFont.systemFont(ofSize: size)
        guard let family = family, let bangla = font(forFamily: family, size: size) else {
            return system
        }
        let descriptor = system.fontDescriptor.addingAttributes([
            .cascadeList: [bangla.fontDescriptor]
        ])
        return NSFont(descriptor: descriptor, size: size) ?? bangla
    }

    /// Regular-weight member of `family`, or nil if the family isn't installed.
    static func font(forFamily family: String, size: CGFloat) -> NSFont? {
        guard let members = NSFontManager.shared.availableMembers(ofFontFamily: family),
              !members.isEmpty else { return nil }
        // Each member: [postscriptName, styleName, weight, traits]; weight 5 = regular.
        let regular = members.first { ($0.count > 2) && (($0[2] as? Int) == 5) }
            ?? members.first { ($0.count > 3) && ((($0[3] as? UInt) ?? 0) & NSFontTraitMask.boldFontMask.rawValue) == 0 }
            ?? members[0]
        guard let name = regular.first as? String else { return nil }
        return NSFont(name: name, size: size)
    }

    /// Installed font families that can draw Bangla, sorted by name. Enumerates
    /// every family on the Mac, so call it when the Settings tab opens — not per
    /// keystroke.
    static func installedBanglaFamilies() -> [String] {
        let ka = Unicode.Scalar(0x0995)!      // ক
        let aaKar = Unicode.Scalar(0x09BE)!   // া
        var families: [String] = []
        for family in NSFontManager.shared.availableFontFamilies {
            if family.hasPrefix(".") { continue }   // private system faces
            guard let font = font(forFamily: family, size: 12) else { continue }
            let covered = font.coveredCharacterSet
            if covered.contains(ka) && covered.contains(aaKar) {
                families.append(family)
            }
        }
        return families.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// CSS `font-family` value for the welcome window's layout chart, or nil for
    /// the default stack.
    static func cssFontFamily() -> String? {
        guard let family = currentFontFamily() else { return nil }
        let escaped = family.replacingOccurrences(of: "\\", with: "\\\\")
                            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

extension Notification.Name {
    static let lekhoAppearanceChanged = Notification.Name("LekhoAppearanceChanged")
}
