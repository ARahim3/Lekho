import Cocoa

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
    /// Tab content is built on first selection — the layout tab lays out ~70
    /// cards, which shouldn't cost anything until it's actually opened.
    private var pendingTabs: [Int: () -> NSView] = [:]

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

        let items: [(String, String, () -> NSView)] = [
            ("start", "Getting Started", { GettingStartedView() }),
            ("layout", "Avro Layout", { LayoutView() }),
            ("settings", "Settings", { SettingsView() }),
        ]
        for (index, (id, label, make)) in items.enumerated() {
            let item = NSTabViewItem(identifier: id)
            item.label = label
            if index == 0 { item.view = make() } else { pendingTabs[index] = make }
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
        let index = sender.selectedSegment
        if let make = pendingTabs.removeValue(forKey: index) {
            tabView.tabViewItem(at: index).view = make()
        }
        tabView.selectTabViewItem(at: index)
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
    static func keyChip(_ text: String, size: CGFloat = 11.5) -> NSView {
        let chip = RoundedTintView(
            cornerRadius: 5,
            fill: { NSColor.labelColor.withAlphaComponent(0.07) },
            border: { NSColor.separatorColor })
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.withBangla(.monospacedSystemFont(ofSize: size, weight: .medium))
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

    /// Card title row: accent SF Symbol + semibold title, optional subtitle.
    static func cardHeader(symbol: String, title: String, subtitle: String? = nil) -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!)
        icon.symbolConfiguration = .init(pointSize: 15, weight: .medium)
        icon.contentTintColor = .controlAccentColor
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        let text = NSStackView(views: [titleLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        if let subtitle {
            let sub = NSTextField(labelWithString: subtitle)
            sub.font = NSFont.systemFont(ofSize: 12)
            sub.textColor = .secondaryLabelColor
            text.addArrangedSubview(sub)
        }
        let row = NSStackView(views: [icon, text])
        row.spacing = 8
        row.alignment = subtitle == nil ? .centerY : .top
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    /// A vertically scrolling page pinned inside `host`; returns the stack to fill.
    /// `bottomInset` reserves space under the scroll view (e.g. for a button bar).
    static func scrollingPage(in host: NSView, bottomInset: CGFloat = 0) -> NSStackView {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        host.addSubview(scrollView)

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
            scrollView.topAnchor.constraint(equalTo: host.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -bottomInset),
            doc.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            page.topAnchor.constraint(equalTo: doc.topAnchor, constant: 28),
            page.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: pageInset),
            page.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -pageInset),
            page.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -28),
        ])
        return page
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
        let page = WelcomeUI.scrollingPage(in: self, bottomInset: 44)

        // Hero
        let hero = makeHero()
        page.addArrangedSubview(hero)
        page.setCustomSpacing(24, after: hero)

        // Setup steps
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
        let setupHeader = WelcomeUI.cardHeader(
            symbol: "lightbulb", title: "Get started in seconds",
            subtitle: "Follow these steps to start typing in Bangla.")
        stepStack.addArrangedSubview(setupHeader)
        stepStack.setCustomSpacing(16, after: setupHeader)
        for (n, title, note) in steps {
            let row = makeStepRow(number: n, title: title, note: note)
            stepStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stepStack.widthAnchor).isActive = true
        }
        addFullWidth(CardContainer(content: stepStack), to: page, spacingAfter: 16)

        // How to type
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
        let typeHeader = WelcomeUI.cardHeader(symbol: "keyboard", title: "How to type")
        scStack.addArrangedSubview(typeHeader)
        scStack.setCustomSpacing(14, after: typeHeader)
        let table = makeShortcutTable(shortcuts)
        scStack.addArrangedSubview(table)
        table.widthAnchor.constraint(equalTo: scStack.widthAnchor).isActive = true
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

    /// Key → action table: header row, a rule, then one row per shortcut. NSGridView
    /// keeps the two columns aligned; the action column absorbs the spare width.
    private func makeShortcutTable(_ shortcuts: [(String, String)]) -> NSView {
        let grid = NSGridView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 10
        grid.columnSpacing = 24
        grid.yPlacement = .center

        func header(_ text: String) -> NSTextField {
            let label = NSTextField(labelWithString: text.uppercased())
            label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            label.textColor = .secondaryLabelColor
            return label
        }
        grid.addRow(with: [header("Key"), header("Action")])

        let rule = NSBox()
        rule.boxType = .separator
        let ruleRow = grid.addRow(with: [rule, NSGridCell.emptyContentView])
        ruleRow.mergeCells(in: NSRange(location: 0, length: 2))
        ruleRow.cell(at: 0).xPlacement = .fill

        var chips: [NSView] = []
        for (key, desc) in shortcuts {
            let chip = WelcomeUI.keyChip(key, size: 13)
            chips.append(chip)
            let label = NSTextField(labelWithString: desc)
            label.font = NSFont.systemFont(ofSize: 14)
            grid.addRow(with: [chip, label])
        }
        // Spare width would otherwise be split across both columns; pin the key
        // column to its widest chip so the actions sit right next to the keys.
        grid.column(at: 0).width = chips.map { $0.fittingSize.width }.max() ?? 0
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .fill
        return grid
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

// MARK: - Avro Layout Tab (searchable card grid)

/// Bangla ↔ Avro key mapping. Vowels show the independent letter and its sign on ক;
/// standalone combining marks sit on a dotted circle (◌) so they're visible.
/// Verified against riti: ` breaks joining (k`i → কই, not কি); ~ is a literal, not
/// ZWNJ; there is no standalone nukta key (ড় ঢ় য় come from R, Rh, y).
private let layoutSections: [(title: String, symbol: String, items: [(bn: String, key: String)])] = [
    ("Consonants", "textformat", [
        ("ক", "k"), ("খ", "kh"), ("গ", "g"), ("ঘ", "gh"), ("ঙ", "Ng"),
        ("চ", "c"), ("ছ", "ch"), ("জ", "j"), ("ঝ", "jh"), ("ঞ", "NG"),
        ("ট", "T"), ("ঠ", "Th"), ("ড", "D"), ("ঢ", "Dh"), ("ণ", "N"),
        ("ত", "t"), ("থ", "th"), ("দ", "d"), ("ধ", "dh"), ("ন", "n"),
        ("প", "p"), ("ফ", "ph, f"), ("ব", "b"), ("ভ", "bh, v"), ("ম", "m"),
        ("য", "z"), ("র", "r"), ("ল", "l"), ("শ", "sh, S"), ("ষ", "Sh"),
        ("স", "s"), ("হ", "h"), ("ড়", "R"), ("ঢ়", "Rh"), ("য়", "y, Y"),
        ("ৎ", "t``"), ("ং", "ng"), ("ঃ", ":"), ("◌ঁ", "^"),
    ]),
    ("Vowels", "character", [
        ("অ", "o"), ("আ / কা", "a"), ("ই / কি", "i"), ("ঈ / কী", "I"), ("উ / কু", "u"),
        ("ঊ / কূ", "U"), ("ঋ / কৃ", "rri"), ("এ / কে", "e"), ("ঐ / কৈ", "OI"), ("ও / কো", "O"),
        ("ঔ / কৌ", "OU"),
    ]),
    ("Special", "sparkles", [
        ("◌্ হসন্ত", ",,"), ("ব-ফলা", "w"), ("য-ফলা", "y, Z"), ("র-ফলা", "r"), ("রেফ", "rr"),
        ("। দাড়ি", "."), ("৳ টাকা", "$"), ("Separator", "`"),
    ]),
    ("Numbers", "number", [
        ("০", "0"), ("১", "1"), ("২", "2"), ("৩", "3"), ("৪", "4"),
        ("৫", "5"), ("৬", "6"), ("৭", "7"), ("৮", "8"), ("৯", "9"),
    ]),
]

class LayoutView: NSView {
    private let search = NSSearchField()
    private let sections = NSStackView()
    private let columns = 5

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        let page = WelcomeUI.scrollingPage(in: self)

        search.placeholderString = "Search keys, characters…"
        search.sendsSearchStringImmediately = true
        search.target = self
        search.action = #selector(searchChanged)
        page.addArrangedSubview(search)
        search.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true
        page.setCustomSpacing(16, after: search)

        sections.orientation = .vertical
        sections.alignment = .leading
        sections.spacing = 16
        page.addArrangedSubview(sections)
        sections.widthAnchor.constraint(equalTo: page.widthAnchor).isActive = true

        rebuild(filter: "")
    }

    @objc private func searchChanged() { rebuild(filter: search.stringValue) }

    /// Cards are cheap (~70), so filtering just rebuilds the grid.
    private func rebuild(filter: String) {
        sections.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        for section in layoutSections {
            let items = q.isEmpty ? section.items
                : section.items.filter { $0.key.lowercased().contains(q) || $0.bn.contains(q) }
            if items.isEmpty { continue }
            let card = CardContainer(
                content: makeSection(section.title, symbol: section.symbol, items: items),
                insets: NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
            sections.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: sections.widthAnchor).isActive = true
        }
    }

    private func makeSection(_ title: String, symbol: String, items: [(bn: String, key: String)]) -> NSView {
        let grid = NSStackView()
        grid.orientation = .vertical
        grid.spacing = 8
        for start in stride(from: 0, to: items.count, by: columns) {
            let row = NSStackView()
            row.distribution = .fillEqually
            row.spacing = 8
            for item in items[start..<min(start + columns, items.count)] {
                row.addArrangedSubview(makeCard(item))
            }
            // Pad the last row so its cards keep the same width as the others.
            while row.arrangedSubviews.count < columns { row.addArrangedSubview(NSView()) }
            grid.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true
        }

        let header = WelcomeUI.cardHeader(symbol: symbol, title: title)
        let content = NSStackView(views: [header, grid])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        grid.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        return content
    }

    private func makeCard(_ item: (bn: String, key: String)) -> NSView {
        let card = RoundedTintView(
            cornerRadius: 8,
            fill: { .controlBackgroundColor },
            border: { .separatorColor })
        let bn = NSTextField(labelWithString: item.bn)
        bn.font = NSFont.withBangla(.systemFont(ofSize: 17, weight: .medium))
        bn.alignment = .center
        let key = NSTextField(labelWithString: item.key)
        key.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        key.textColor = .secondaryLabelColor
        key.alignment = .center
        let stack = NSStackView(views: [bn, key])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 58),
            stack.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
        ])
        return card
    }
}
