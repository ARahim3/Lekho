import Cocoa
import WebKit

// MARK: - Window Controller (Singleton)

class WelcomeWindowController {
    static let shared = WelcomeWindowController()

    private var window: NSWindow?

    func showWindow() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 740),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Lekho"
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.contentView = WelcomeTabView()
        window.center()

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Tabbed Container

class WelcomeTabView: NSView {
    private let tabView = NSTabView()
    private let segmented = NSSegmentedControl()

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupTabs()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupTabs() {
        // Hide NSTabView's own (flat) tabs; we drive selection with a clearly
        // clickable segmented control instead.
        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.tabViewType = .noTabsNoBorder

        let items: [(String, String, NSView)] = [
            ("start", "Getting Started", GettingStartedView()),
            ("layout", "Avro Layout", LayoutWebView()),
            ("settings", "Settings", SettingsView()),
        ]
        for (id, label, view) in items {
            let item = NSTabViewItem(identifier: id)
            item.label = label
            item.view = view
            tabView.addTabViewItem(item)
        }

        segmented.segmentCount = items.count
        for (index, item) in items.enumerated() {
            segmented.setLabel(item.1, forSegment: index)
            segmented.setWidth(0, forSegment: index)  // auto-size to label
        }
        segmented.segmentStyle = .automatic
        segmented.trackingMode = .selectOne
        segmented.controlSize = .large
        segmented.selectedSegment = 0
        segmented.target = self
        segmented.action = #selector(segmentChanged(_:))
        segmented.translatesAutoresizingMaskIntoConstraints = false

        addSubview(segmented)
        addSubview(tabView)

        NSLayoutConstraint.activate([
            segmented.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            segmented.centerXAnchor.constraint(equalTo: centerXAnchor),

            tabView.topAnchor.constraint(equalTo: segmented.bottomAnchor, constant: 10),
            tabView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tabView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @objc private func segmentChanged(_ sender: NSSegmentedControl) {
        tabView.selectTabViewItem(at: sender.selectedSegment)
    }
}

// MARK: - Settings Tab

// MARK: - Shared welcome-window UI

/// Visual helpers shared across the welcome window's tabs.
enum WelcomeUI {
    static let pageInset: CGFloat = 28
    static let accentTint: CGFloat = 0.12

    /// Small uppercase section header (macOS grouped-settings style).
    static func sectionHeader(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        let attr = NSMutableAttributedString(string: text.uppercased())
        attr.addAttributes(
            [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
                .kern: 0.6,
            ],
            range: NSRange(location: 0, length: attr.length))
        label.attributedStringValue = attr
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    /// A monospace "key" chip used in the shortcut/layout lists.
    static func keyChip(_ text: String) -> NSView {
        let chip = RoundedTintView(
            cornerRadius: 5,
            fill: { NSColor.labelColor.withAlphaComponent(0.07) },
            border: { NSColor.separatorColor })
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .medium)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        chip.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -7),
            label.topAnchor.constraint(equalTo: chip.topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: -2),
        ])
        return chip
    }
}

/// A rounded, layer-backed view whose fill/border colors resolve per-appearance.
/// `fill`/`border` are closures so semantic NSColors are re-resolved on light/dark
/// changes (CGColors don't auto-update).
class RoundedTintView: NSView {
    private let fillColor: () -> NSColor
    private let borderColor: (() -> NSColor)?

    init(cornerRadius: CGFloat, borderWidth: CGFloat = 1,
         fill: @escaping () -> NSColor, border: (() -> NSColor)? = nil) {
        self.fillColor = fill
        self.borderColor = border
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.borderWidth = border == nil ? 0 : borderWidth
        translatesAutoresizingMaskIntoConstraints = false
        applyColors()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    func refreshColors() { applyColors() }

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance { [self] in
            layer?.backgroundColor = fillColor().cgColor
            if let borderColor { layer?.borderColor = borderColor().cgColor }
        }
    }
}

/// A rounded container that wraps arbitrary content with inset padding.
final class CardContainer: RoundedTintView {
    init(content: NSView, insets: NSEdgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)) {
        super.init(
            cornerRadius: 10,
            fill: { .controlBackgroundColor.withAlphaComponent(0.6) },
            border: { .separatorColor })
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Small accent "Recommended"-style badge.
final class PillBadge: RoundedTintView {
    init(text: String) {
        super.init(
            cornerRadius: 7,
            fill: { .controlAccentColor.withAlphaComponent(0.15) })
        setContentHuggingPriority(.required, for: .horizontal)
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .controlAccentColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Settings Tab (selectable mode cards)

/// A selectable typing-mode card: radio indicator + title (+ optional badge) +
/// wrapping description. The whole card is clickable.
final class ModeCard: NSView {
    let mode: LekhoInputController.TypingMode
    var onSelect: (() -> Void)?
    var isSelected: Bool = false { didSet { updateSelection() } }

    private let radio = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let descLabel = NSTextField(wrappingLabelWithString: "")

    init(mode: LekhoInputController.TypingMode, title: String, description: String, recommended: Bool) {
        self.mode = mode
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false

        radio.translatesAutoresizingMaskIntoConstraints = false
        radio.imageScaling = .scaleProportionallyUpOrDown

        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)

        descLabel.stringValue = description
        descLabel.font = NSFont.systemFont(ofSize: 13)
        descLabel.textColor = .secondaryLabelColor
        descLabel.translatesAutoresizingMaskIntoConstraints = false

        let titleRow = NSStackView(views: [titleLabel])
        titleRow.orientation = .horizontal
        titleRow.spacing = 8
        titleRow.alignment = .centerY
        if recommended { titleRow.addArrangedSubview(PillBadge(text: "Recommended")) }
        titleRow.translatesAutoresizingMaskIntoConstraints = false

        addSubview(radio)
        addSubview(titleRow)
        addSubview(descLabel)

        NSLayoutConstraint.activate([
            radio.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            radio.topAnchor.constraint(equalTo: topAnchor, constant: 17),
            radio.widthAnchor.constraint(equalToConstant: 16),
            radio.heightAnchor.constraint(equalToConstant: 16),

            titleRow.leadingAnchor.constraint(equalTo: radio.trailingAnchor, constant: 12),
            titleRow.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            titleRow.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),

            descLabel.leadingAnchor.constraint(equalTo: titleRow.leadingAnchor),
            descLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            descLabel.topAnchor.constraint(equalTo: titleRow.bottomAnchor, constant: 4),
            descLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])

        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(clicked)))
        updateSelection()
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func clicked() { onSelect?() }

    private func updateSelection() {
        let symbol = isSelected ? "largecircle.fill.circle" : "circle"
        radio.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        radio.contentTintColor = isSelected ? .controlAccentColor : .tertiaryLabelColor
        applyColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance { [self] in
            if isSelected {
                layer?.borderColor = NSColor.controlAccentColor.cgColor
                layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
            } else {
                layer?.borderColor = NSColor.separatorColor.cgColor
                layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.55).cgColor
            }
        }
    }
}

class SettingsView: NSView {
    private var cards: [ModeCard] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        let header = WelcomeUI.sectionHeader("Typing mode")

        let intro = NSTextField(wrappingLabelWithString:
            "Choose how Lekho turns what you type into Bangla. You can switch anytime.")
        intro.font = NSFont.systemFont(ofSize: 13)
        intro.textColor = .secondaryLabelColor
        intro.translatesAutoresizingMaskIntoConstraints = false

        let cardStack = NSStackView()
        cardStack.orientation = .vertical
        cardStack.alignment = .leading
        cardStack.spacing = 14
        cardStack.translatesAutoresizingMaskIntoConstraints = false

        let current = LekhoInputController.currentTypingMode()
        let modes: [(LekhoInputController.TypingMode, String, String, Bool)] = [
            (.smart, "Smart suggestions",
             "Dictionary, autocorrect, and emoji choose the best-matching word when you press space. Press a number, the arrow keys, or click to pick another.",
             false),
            (.phoneticFirst, "Phonetic-first",
             "Your exact phonetic spelling is committed by default, but the suggestion list is still right there — reach for a dictionary word whenever you want one. Lekho remembers the words you deliberately pick.",
             true),
            (.phoneticOnly, "Phonetic-only",
             "Pure transliteration with no suggestion popup, autocorrect, or emoji. Full control over every word — but no dictionary fixes for irregular spellings.",
             false),
        ]
        for (mode, title, desc, recommended) in modes {
            let card = ModeCard(mode: mode, title: title, description: desc, recommended: recommended)
            card.isSelected = (mode == current)
            card.onSelect = { [weak self] in self?.select(mode) }
            cards.append(card)
            cardStack.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: cardStack.widthAnchor).isActive = true
        }

        let content = NSStackView(views: [header, intro, cardStack])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 6
        content.setCustomSpacing(18, after: intro)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        let tip = NSTextField(wrappingLabelWithString:
            "Changes apply immediately to new typing. Any word you were composing when you switch is discarded — just retype it.")
        tip.font = NSFont.systemFont(ofSize: 11)
        tip.textColor = .tertiaryLabelColor
        tip.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tip)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: WelcomeUI.pageInset),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -WelcomeUI.pageInset),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 28),
            cardStack.widthAnchor.constraint(equalTo: content.widthAnchor),
            intro.widthAnchor.constraint(equalTo: content.widthAnchor),

            tip.leadingAnchor.constraint(equalTo: leadingAnchor, constant: WelcomeUI.pageInset),
            tip.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -WelcomeUI.pageInset),
            tip.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24),
        ])
    }

    private func select(_ mode: LekhoInputController.TypingMode) {
        for card in cards { card.isSelected = (card.mode == mode) }
        UserDefaults.standard.set(mode.rawValue, forKey: LekhoInputController.typingModeKey)
        NotificationCenter.default.post(name: .lekhoTypingModeChanged, object: nil)
    }
}

// MARK: - Getting Started Tab

class GettingStartedView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        setupCheckForUpdateButton()

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -44),
        ])

        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = doc

        let page = NSStackView()
        page.orientation = .vertical
        page.alignment = .leading
        page.spacing = 10
        page.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(page)

        NSLayoutConstraint.activate([
            doc.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            page.topAnchor.constraint(equalTo: doc.topAnchor, constant: 28),
            page.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: WelcomeUI.pageInset),
            page.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -WelcomeUI.pageInset),
            page.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -28),
        ])

        // Hero
        let hero = makeHero()
        page.addArrangedSubview(hero)
        page.setCustomSpacing(24, after: hero)

        // Setup steps
        let setupHeader = WelcomeUI.sectionHeader("Setup")
        page.addArrangedSubview(setupHeader)
        page.setCustomSpacing(8, after: setupHeader)

        let steps: [(Int, String, String?)] = [
            (1, "Log out and log back in", "Only if you just installed Lekho for the first time."),
            (2, "Open System Settings \u{2192} Keyboard \u{2192} Input Sources", nil),
            (3, "Click +, search \u{201C}Lekho\u{201D}, select it, and add it", nil),
            (4, "Switch with the Globe key or Ctrl+Space", nil),
        ]
        let stepStack = NSStackView()
        stepStack.orientation = .vertical
        stepStack.alignment = .leading
        stepStack.spacing = 12
        stepStack.translatesAutoresizingMaskIntoConstraints = false
        for (n, title, note) in steps {
            let row = makeStepRow(number: n, title: title, note: note)
            stepStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stepStack.widthAnchor).isActive = true
        }
        addFullWidth(CardContainer(content: stepStack), to: page, spacingAfter: 22)

        // How to type
        let typeHeader = WelcomeUI.sectionHeader("How to type")
        page.addArrangedSubview(typeHeader)
        page.setCustomSpacing(8, after: typeHeader)

        let shortcuts: [(String, String)] = [
            ("ami \u{2192} \u{0986}\u{09AE}\u{09BF}", "Type in English, phonetically"),
            ("Space", "Commit the highlighted suggestion"),
            ("1\u{2013}9", "Pick a specific candidate from the list"),
            ("\u{2191} \u{2193}", "Move through the candidate list"),
            ("Backspace", "Delete the last character"),
            ("Esc", "Cancel the current word"),
        ]
        let scStack = NSStackView()
        scStack.orientation = .vertical
        scStack.alignment = .leading
        scStack.spacing = 10
        scStack.translatesAutoresizingMaskIntoConstraints = false
        for (key, desc) in shortcuts {
            let row = makeShortcutRow(key: key, desc: desc)
            scStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: scStack.widthAnchor).isActive = true
        }
        addFullWidth(CardContainer(content: scStack), to: page, spacingAfter: 16)

        // Tip
        let tip = NSTextField(wrappingLabelWithString:
            "You can close this window — the keyboard keeps running in the background. Open Lekho "
            + "anytime to see this guide, or check the Avro Layout tab for the full key mapping.")
        tip.font = NSFont.systemFont(ofSize: 12)
        tip.textColor = .secondaryLabelColor
        tip.translatesAutoresizingMaskIntoConstraints = false
        addFullWidth(tip, to: page, spacingAfter: 26)

        // Footer
        addFullWidth(makeFooter(), to: page)
    }

    private func addFullWidth(_ view: NSView, to stack: NSStackView, spacingAfter: CGFloat? = nil) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        if let spacing = spacingAfter { stack.setCustomSpacing(spacing, after: view) }
    }

    private func makeHero() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        row.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 60),
            icon.heightAnchor.constraint(equalToConstant: 60),
        ])

        let title = NSTextField(labelWithString: "Welcome to Lekho")
        title.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        let subtitle = NSTextField(labelWithString: "Avro Phonetic Bangla keyboard for macOS")
        subtitle.font = NSFont.systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor

        let textCol = NSStackView(views: [title, subtitle])
        textCol.orientation = .vertical
        textCol.alignment = .leading
        textCol.spacing = 2

        row.addArrangedSubview(icon)
        row.addArrangedSubview(textCol)
        return row
    }

    private func makeNumberBadge(_ n: Int) -> NSView {
        let badge = RoundedTintView(
            cornerRadius: 11, borderWidth: 0,
            fill: { NSColor.controlAccentColor.withAlphaComponent(0.15) })
        badge.setContentHuggingPriority(.required, for: .horizontal)
        let label = NSTextField(labelWithString: "\(n)")
        label.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        label.textColor = .controlAccentColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(label)
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 22),
            badge.heightAnchor.constraint(equalToConstant: 22),
            label.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
        ])
        return badge
    }

    private func makeStepRow(number: Int, title: String, note: String?) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let badge = makeNumberBadge(number)
        let titleLabel = NSTextField(wrappingLabelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(badge)
        row.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            badge.topAnchor.constraint(equalTo: row.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 1),
        ])

        if let note = note, !note.isEmpty {
            let noteLabel = NSTextField(wrappingLabelWithString: note)
            noteLabel.font = NSFont.systemFont(ofSize: 12)
            noteLabel.textColor = .secondaryLabelColor
            noteLabel.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(noteLabel)
            NSLayoutConstraint.activate([
                noteLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
                noteLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                noteLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
                noteLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            ])
        } else {
            titleLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor).isActive = true
        }
        return row
    }

    private func makeShortcutRow(key: String, desc: String) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let chip = WelcomeUI.keyChip(key)
        chip.setContentHuggingPriority(.required, for: .horizontal)
        let descLabel = NSTextField(wrappingLabelWithString: desc)
        descLabel.font = NSFont.systemFont(ofSize: 12)
        descLabel.textColor = .secondaryLabelColor
        descLabel.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(chip)
        row.addSubview(descLabel)
        NSLayoutConstraint.activate([
            chip.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            chip.topAnchor.constraint(equalTo: row.topAnchor),
            chip.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor),
            descLabel.leadingAnchor.constraint(equalTo: chip.trailingAnchor, constant: 12),
            descLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            descLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 1),
            descLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])
        return row
    }

    private func makeFooter() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        let credit = NSTextField(labelWithString: "Maintained by Abdur Rahim")
        credit.font = NSFont.systemFont(ofSize: 11)
        credit.textColor = .secondaryLabelColor

        let dot = NSTextField(labelWithString: "\u{00B7}")
        dot.font = NSFont.systemFont(ofSize: 11)
        dot.textColor = .tertiaryLabelColor

        let links = NSStackView(views: [
            makeLinkButton("github.com/ARahim3", url: "https://github.com/ARahim3"),
            dot,
            makeLinkButton("arahim3.github.io", url: "https://arahim3.github.io"),
        ])
        links.orientation = .horizontal
        links.spacing = 8
        links.alignment = .centerY

        let powered = NSTextField(wrappingLabelWithString:
            "Powered by OpenBangla\u{2019}s riti engine. Built for the Bengali community on macOS.")
        powered.font = NSFont.systemFont(ofSize: 10)
        powered.textColor = .tertiaryLabelColor
        powered.alignment = .center
        powered.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(divider)
        stack.setCustomSpacing(12, after: divider)
        stack.addArrangedSubview(credit)
        stack.addArrangedSubview(links)
        stack.setCustomSpacing(8, after: links)
        stack.addArrangedSubview(powered)

        NSLayoutConstraint.activate([
            divider.widthAnchor.constraint(equalTo: stack.widthAnchor),
            powered.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return stack
    }

    private func makeLinkButton(_ title: String, url: String) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(openLink(_:)))
        button.isBordered = false
        button.bezelStyle = .inline
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.controlAccentColor,
            .font: NSFont.systemFont(ofSize: 11),
        ])
        button.identifier = NSUserInterfaceItemIdentifier(url)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    @objc private func openLink(_ sender: NSButton) {
        if let raw = sender.identifier?.rawValue, let url = URL(string: raw) {
            NSWorkspace.shared.open(url)
        }
    }

    private func setupCheckForUpdateButton() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)

        let button = NSButton(title: "Check for Update", target: self, action: #selector(checkForUpdate))
        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            container.heightAnchor.constraint(equalToConstant: 32),
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
    }

    @objc private func checkForUpdate() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let url = URL(string: "https://api.github.com/repos/ARahim3/Lekho/releases/latest")!

        var request = URLRequest(url: url)
        request.setValue("Lekho/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.showUpdateAlert(
                        title: "Connection Error",
                        message: "Could not check for updates. Please check your internet connection.\n\n\(error.localizedDescription)"
                    )
                    return
                }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String else {
                    self.showUpdateAlert(
                        title: "Check Failed",
                        message: "Could not read release information from GitHub."
                    )
                    return
                }

                // Strip leading "v" if present (e.g. "v0.2.0" → "0.2.0")
                let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

                if self.isVersion(latestVersion, newerThan: currentVersion) {
                    let htmlURL = json["html_url"] as? String ?? "https://github.com/ARahim3/Lekho/releases/latest"
                    self.showUpdateAvailableAlert(latestVersion: latestVersion, downloadURL: htmlURL)
                } else {
                    self.showUpdateAlert(
                        title: "You\u{2019}re Up to Date",
                        message: "Lekho \(currentVersion) is the latest version."
                    )
                }
            }
        }.resume()
    }

    private func isVersion(_ a: String, newerThan b: String) -> Bool {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(aParts.count, bParts.count) {
            let aVal = i < aParts.count ? aParts[i] : 0
            let bVal = i < bParts.count ? bParts[i] : 0
            if aVal > bVal { return true }
            if aVal < bVal { return false }
        }
        return false
    }

    private func showUpdateAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showUpdateAvailableAlert(latestVersion: String, downloadURL: String) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "Lekho \(latestVersion) is available. You are currently running \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: downloadURL) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

// MARK: - Avro Layout Tab (WKWebView for proper Bengali rendering)

class LayoutWebView: NSView {
    private var webView: WKWebView!

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupWebView()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        webView.loadHTMLString(layoutHTML(), baseURL: nil)
    }

    private func layoutHTML() -> String {
        return """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="utf-8">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                :root {
                    --accent: #007aff;
                    --text: #1d1d1f;
                    --text-secondary: #8a8a8e;
                    --card-bg: rgba(0, 0, 0, 0.025);
                    --card-border: rgba(0, 0, 0, 0.10);
                    --row-border: rgba(0, 0, 0, 0.06);
                }
                @media (prefers-color-scheme: dark) {
                    :root {
                        --accent: #6cb4ee;
                        --text: #f2f2f7;
                        --text-secondary: #98989d;
                        --card-bg: rgba(255, 255, 255, 0.05);
                        --card-border: rgba(255, 255, 255, 0.12);
                        --row-border: rgba(255, 255, 255, 0.07);
                    }
                }
                body {
                    font-family: -apple-system, "Helvetica Neue", sans-serif;
                    padding: 16px 18px;
                    background: transparent;
                    color-scheme: light dark;
                    color: var(--text);
                }
                .section-title {
                    color: var(--text-secondary);
                    font-size: 10.5px;
                    font-weight: 600;
                    letter-spacing: 0.5px;
                    text-transform: uppercase;
                    margin: 16px 0 5px 2px;
                }
                .section-title:first-child { margin-top: 0; }
                table {
                    width: 100%;
                    table-layout: fixed;
                    border-collapse: separate;
                    border-spacing: 0;
                    background: var(--card-bg);
                    border: 1px solid var(--card-border);
                    border-radius: 10px;
                    overflow: hidden;
                }
                td {
                    padding: 4px 6px;
                    border-bottom: 1px solid var(--row-border);
                    vertical-align: middle;
                    font-size: 12px;
                    line-height: 1.35;
                }
                tr:last-child td { border-bottom: none; }
                .bn {
                    font-size: 15px;
                    font-weight: 500;
                    color: var(--text);
                    width: 34px;
                    text-align: center;
                }
                .key {
                    font-size: 11px;
                    font-weight: 600;
                    color: var(--accent);
                    font-family: "SF Mono", Menlo, monospace;
                }
                .pair { width: 25%; }
                .pair-wide { width: 33.33%; }
                .sep { width: 10px; }
            </style>
            </head>
            <body>

            <div class="section-title">Consonants \u{09AC}\u{09CD}\u{09AF}\u{099E}\u{09CD}\u{099C}\u{09A8}\u{09AC}\u{09B0}\u{09CD}\u{09A3}</div>
            <table>
            <tr>
                <td class="bn pair">\u{0995}</td><td class="key">k</td><td class="sep"></td>
                <td class="bn pair">\u{099F}</td><td class="key">T</td><td class="sep"></td>
                <td class="bn pair">\u{09AA}</td><td class="key">p</td><td class="sep"></td>
                <td class="bn pair">\u{09B8}</td><td class="key">s</td>
            </tr>
            <tr>
                <td class="bn">\u{0996}</td><td class="key">kh</td><td class="sep"></td>
                <td class="bn">\u{09A0}</td><td class="key">Th</td><td class="sep"></td>
                <td class="bn">\u{09AB}</td><td class="key">ph, f</td><td class="sep"></td>
                <td class="bn">\u{09B9}</td><td class="key">h</td>
            </tr>
            <tr>
                <td class="bn">\u{0997}</td><td class="key">g</td><td class="sep"></td>
                <td class="bn">\u{09A1}</td><td class="key">D</td><td class="sep"></td>
                <td class="bn">\u{09AC}</td><td class="key">b</td><td class="sep"></td>
                <td class="bn">\u{09DC}</td><td class="key">R</td>
            </tr>
            <tr>
                <td class="bn">\u{0998}</td><td class="key">gh</td><td class="sep"></td>
                <td class="bn">\u{09A2}</td><td class="key">Dh</td><td class="sep"></td>
                <td class="bn">\u{09AD}</td><td class="key">bh, v</td><td class="sep"></td>
                <td class="bn">\u{09DD}</td><td class="key">Rh</td>
            </tr>
            <tr>
                <td class="bn">\u{0999}</td><td class="key">Ng</td><td class="sep"></td>
                <td class="bn">\u{09A3}</td><td class="key">N</td><td class="sep"></td>
                <td class="bn">\u{09AE}</td><td class="key">m</td><td class="sep"></td>
                <td class="bn">\u{09DF}</td><td class="key">y, Y</td>
            </tr>
            <tr>
                <td class="bn">\u{099A}</td><td class="key">c</td><td class="sep"></td>
                <td class="bn">\u{09A4}</td><td class="key">t</td><td class="sep"></td>
                <td class="bn">\u{09AF}</td><td class="key">z</td><td class="sep"></td>
                <td class="bn">\u{09B6}</td><td class="key">sh, S</td>
            </tr>
            <tr>
                <td class="bn">\u{099B}</td><td class="key">ch</td><td class="sep"></td>
                <td class="bn">\u{09A5}</td><td class="key">th</td><td class="sep"></td>
                <td class="bn">\u{09B0}</td><td class="key">r</td><td class="sep"></td>
                <td class="bn">\u{09B7}</td><td class="key">Sh</td>
            </tr>
            <tr>
                <td class="bn">\u{099C}</td><td class="key">j</td><td class="sep"></td>
                <td class="bn">\u{09A6}</td><td class="key">d</td><td class="sep"></td>
                <td class="bn">\u{09B2}</td><td class="key">l</td><td class="sep"></td>
                <td class="bn">\u{0982}</td><td class="key">ng</td>
            </tr>
            <tr>
                <td class="bn">\u{099D}</td><td class="key">jh</td><td class="sep"></td>
                <td class="bn">\u{09A7}</td><td class="key">dh</td><td class="sep"></td>
                <td class="bn">\u{0983}</td><td class="key">:</td><td class="sep"></td>
                <td class="bn">\u{0981}</td><td class="key">^</td>
            </tr>
            <tr>
                <td class="bn">\u{099E}</td><td class="key">NG</td><td class="sep"></td>
                <td class="bn">\u{09A8}</td><td class="key">n</td><td class="sep"></td>
                <td class="bn">\u{09CE}</td><td class="key">t``</td><td class="sep"></td>
                <td class="bn"></td><td class="key"></td>
            </tr>
            </table>

            <div class="section-title">Vowels \u{09B8}\u{09CD}\u{09AC}\u{09B0}\u{09AC}\u{09B0}\u{09CD}\u{09A3}</div>
            <table>
            <tr>
                <td class="bn pair-wide">\u{0985}</td><td class="key">o</td><td class="sep"></td>
                <td class="bn pair-wide">\u{0987} / \u{0995}\u{09BF}</td><td class="key">i</td><td class="sep"></td>
                <td class="bn pair-wide">\u{0989} / \u{0995}\u{09C1}</td><td class="key">u</td>
            </tr>
            <tr>
                <td class="bn">\u{0986} / \u{0995}\u{09BE}</td><td class="key">a</td><td class="sep"></td>
                <td class="bn">\u{0988} / \u{0995}\u{09C0}</td><td class="key">I</td><td class="sep"></td>
                <td class="bn">\u{098A} / \u{0995}\u{09C2}</td><td class="key">U</td>
            </tr>
            <tr>
                <td class="bn">\u{098B} / \u{0995}\u{09C3}</td><td class="key">rri</td><td class="sep"></td>
                <td class="bn">\u{098F} / \u{0995}\u{09C7}</td><td class="key">e</td><td class="sep"></td>
                <td class="bn">\u{0993} / \u{0995}\u{09CB}</td><td class="key">O</td>
            </tr>
            <tr>
                <td class="bn">\u{0990} / \u{0995}\u{09C8}</td><td class="key">OI</td><td class="sep"></td>
                <td class="bn">\u{0994} / \u{0995}\u{09CC}</td><td class="key">OU</td><td class="sep"></td>
                <td class="bn"></td><td class="key"></td>
            </tr>
            </table>

            <div class="section-title">Special</div>
            <table>
            <tr>
                <td class="bn pair-wide">\u{09CD} \u{09B9}\u{09B8}\u{09A8}\u{09CD}\u{09A4}</td><td class="key">,,</td><td class="sep"></td>
                <td class="bn pair-wide">\u{09AC}-\u{09AB}\u{09B2}\u{09BE}</td><td class="key">w</td><td class="sep"></td>
                <td class="bn pair-wide">\u{09B0}\u{09C7}\u{09AB}</td><td class="key">rr (v)</td>
            </tr>
            <tr>
                <td class="bn">\u{09BC} \u{09A8}\u{09C1}\u{0995}\u{09CD}\u{09A4}\u{09BE}</td><td class="key">..</td><td class="sep"></td>
                <td class="bn">\u{09AF}-\u{09AB}\u{09B2}\u{09BE}</td><td class="key">y, Z</td><td class="sep"></td>
                <td class="bn">\u{0964} \u{09A6}\u{09BE}\u{09DC}\u{09BF}</td><td class="key">.</td>
            </tr>
            <tr>
                <td class="bn">ZWJ</td><td class="key">`</td><td class="sep"></td>
                <td class="bn">\u{09B0}-\u{09AB}\u{09B2}\u{09BE}</td><td class="key">r</td><td class="sep"></td>
                <td class="bn">\u{09F3} \u{099F}\u{09BE}\u{0995}\u{09BE}</td><td class="key">$</td>
            </tr>
            <tr>
                <td class="bn">ZWNJ</td><td class="key">~</td><td class="sep"></td>
                <td class="bn"></td><td class="key"></td><td class="sep"></td>
                <td class="bn"></td><td class="key"></td>
            </tr>
            </table>

            <div class="section-title">Numbers \u{09B8}\u{0982}\u{0996}\u{09CD}\u{09AF}\u{09BE}</div>
            <table>
            <tr>
                <td class="bn">\u{09E6}</td><td class="key">0</td><td class="sep"></td>
                <td class="bn">\u{09E7}</td><td class="key">1</td><td class="sep"></td>
                <td class="bn">\u{09E8}</td><td class="key">2</td><td class="sep"></td>
                <td class="bn">\u{09E9}</td><td class="key">3</td><td class="sep"></td>
                <td class="bn">\u{09EA}</td><td class="key">4</td>
            </tr>
            <tr>
                <td class="bn">\u{09EB}</td><td class="key">5</td><td class="sep"></td>
                <td class="bn">\u{09EC}</td><td class="key">6</td><td class="sep"></td>
                <td class="bn">\u{09ED}</td><td class="key">7</td><td class="sep"></td>
                <td class="bn">\u{09EE}</td><td class="key">8</td><td class="sep"></td>
                <td class="bn">\u{09EF}</td><td class="key">9</td>
            </tr>
            </table>

            </body>
            </html>
            """
    }
}
