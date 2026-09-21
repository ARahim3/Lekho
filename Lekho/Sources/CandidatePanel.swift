import Cocoa

/// Bundled word list, used to mark candidates whose spelling is a known dictionary word.
enum SpellingDictionary {
    /// Set once loading finishes (on the main thread); until then lookups report false.
    private static var words: Set<String>?

    /// Call at launch. Parses off the main thread and never blocks typing.
    static func preload() {
        guard words == nil else { return }
        DispatchQueue.global(qos: .utility).async {
            guard let url = Bundle.main.url(forResource: "dictionary", withExtension: "json", subdirectory: "data"),
                  let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String]] else { return }
            // Swift String equality is canonical, so য় ড় ঢ় ো match in either encoding.
            var set = Set<String>(minimumCapacity: 160_000)
            for list in json.values { set.formUnion(list) }
            DispatchQueue.main.async { words = set }
        }
    }

    static func contains(_ word: String) -> Bool { words?.contains(word) ?? false }
}

class CandidatePanel {
    private var panel: NSPanel?
    private var contentView: CandidateView?
    /// Transparent margin around the glass that holds the custom shadow (0 without glass).
    private var shadowMargin: CGFloat { panel?.contentView is ShadowContainer ? ShadowContainer.margin : 0 }

    /// Called when user clicks a candidate. Parameter is the candidate index.
    var onCandidateSelected: ((Int) -> Void)?

    func show(candidates: [String], auxiliaryText: String, selectedIndex: Int, cursorRect: NSRect) {
        if panel == nil {
            createPanel()
        }

        guard let panel = panel, let contentView = contentView else { return }

        contentView.update(candidates: candidates, auxiliaryText: auxiliaryText, selectedIndex: selectedIndex)

        // Size the panel to fit content
        let size = contentView.idealSize()
        panel.setContentSize(NSSize(width: size.width + shadowMargin * 2, height: size.height + shadowMargin * 2))

        // Position below the cursor (macOS coords: y increases upward)
        var origin = cursorRect.origin
        origin.y -= size.height + 4  // 4px gap below cursor line

        // Find the screen containing the cursor
        let cursorPoint = NSPoint(x: cursorRect.midX, y: cursorRect.midY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(cursorPoint) }) ?? NSScreen.main

        if let screen = screen {
            let sf = screen.visibleFrame

            // Horizontal: keep panel fully on screen
            origin.x = max(sf.minX, min(origin.x, sf.maxX - size.width))

            // Vertical: prefer below cursor; if not enough room, flip above
            if origin.y < sf.minY {
                origin.y = cursorRect.maxY + 4  // above the cursor
            }
            // If STILL off-screen (cursor near top), clamp to top
            if origin.y + size.height > sf.maxY {
                origin.y = sf.maxY - size.height
            }
            // Final clamp
            if origin.y < sf.minY {
                origin.y = sf.minY
            }
        }

        panel.setFrameOrigin(NSPoint(x: origin.x - shadowMargin, y: origin.y - shadowMargin))
        panel.orderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func selectCandidate(at index: Int) {
        contentView?.setSelectedIndex(index)
    }

    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 250, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let contentView = CandidateView()
        contentView.onCandidateClicked = { [weak self] index in
            self?.onCandidateSelected?(index)
        }
        if #available(macOS 26, *) {
            // Native Liquid Glass; the view stops painting its own background.
            let glass = NSGlassEffectView()
            glass.cornerRadius = ShadowContainer.cornerRadius
            glass.contentView = contentView
            contentView.rowRadius = 8
            // The system shadow can't be tuned, so draw our own in a margin around the glass.
            panel.hasShadow = false
            panel.contentView = ShadowContainer(glass: glass)
        } else {
            panel.contentView = FlatBackground(content: contentView)
        }

        self.panel = panel
        self.contentView = contentView
    }
}

// MARK: - FlatBackground

/// Pre-macOS 26 host: the opaque rounded background and hairline border.
private final class FlatBackground: NSView {
    init(content: NSView) {
        super.init(frame: .zero)
        addSubview(content)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        subviews.first?.frame = bounds
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        NSColor.windowBackgroundColor.setFill()
        path.fill()

        NSColor.separatorColor.setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }
}

// MARK: - ShadowContainer

/// Hosts the glass view inset by `margin` and draws a soft, elevated shadow around it.
private final class ShadowContainer: NSView {
    static let cornerRadius: CGFloat = 16
    static let margin: CGFloat = 40
    // Elevation: a bigger blur and a longer downward offset read as "higher".
    private static let blur: CGFloat = 24
    private static let offsetY: CGFloat = -12
    private static let opacity: Float = 0.3

    private let shadowLayer = CALayer()
    private let cutout = CAShapeLayer()

    init(glass: NSView) {
        super.init(frame: .zero)
        wantsLayer = true
        shadowLayer.shadowOpacity = Self.opacity
        shadowLayer.shadowRadius = Self.blur
        shadowLayer.shadowOffset = CGSize(width: 0, height: Self.offsetY)
        shadowLayer.mask = cutout
        cutout.fillRule = .evenOdd
        layer?.addSublayer(shadowLayer)

        addSubview(glass)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var glassRect: NSRect { bounds.insetBy(dx: Self.margin, dy: Self.margin) }

    override func layout() {
        super.layout()
        subviews.first?.frame = glassRect
        let rounded = CGPath(roundedRect: glassRect, cornerWidth: Self.cornerRadius, cornerHeight: Self.cornerRadius, transform: nil)
        shadowLayer.frame = bounds
        shadowLayer.shadowPath = rounded
        // Mask out the glass area so the shadow doesn't tint the translucent glass.
        let path = CGMutablePath()
        path.addRect(bounds)
        path.addPath(rounded)
        cutout.frame = bounds
        cutout.path = path
    }
}

// MARK: - CandidateView

class CandidateView: NSView {
    private var candidates: [String] = []
    private var auxiliaryText: String = ""
    private var selectedIndex: Int = 0
    private var scrollOffset: Int = 0

    /// Called when user clicks a candidate row. Parameter is the candidate index.
    var onCandidateClicked: ((Int) -> Void)?

    /// Selection highlight radius; the glass host sets a larger one to stay concentric with its corners.
    var rowRadius: CGFloat = 4

    private let padding: CGFloat = 8
    private let rowHeight: CGFloat = 28
    /// Space between the selection highlight's edge and its content.
    private let rowInset: CGFloat = 10
    /// Scroll arrows sit this far from the right edge, left of the Enter symbol.
    private let arrowInset: CGFloat = 44
    private let auxHeight: CGFloat = 20
    private let maxVisibleCandidates = 9
    /// System font for English/emoji candidates, bundled July for Bangla ones.
    private static let candidateFont = NSFont.withBangla(.systemFont(ofSize: 17))
    private static let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
    /// Digits share one line height, so measure once.
    private static let numberHeight = "0".size(withAttributes: [.font: numberFont]).height
    /// Measured per candidate in `update`, so drawing never lays text out twice.
    private var wordSizes: [NSSize] = []

    func update(candidates: [String], auxiliaryText: String, selectedIndex: Int) {
        self.candidates = candidates
        self.wordSizes = candidates.map { $0.size(withAttributes: [.font: Self.candidateFont]) }
        self.auxiliaryText = auxiliaryText
        self.selectedIndex = candidates.isEmpty ? 0 : min(selectedIndex, candidates.count - 1)
        adjustScroll()
        needsDisplay = true
    }

    func setSelectedIndex(_ index: Int) {
        self.selectedIndex = candidates.isEmpty ? 0 : min(index, candidates.count - 1)
        adjustScroll()
        needsDisplay = true
    }

    /// Ensure the selected candidate is within the visible scroll window
    private func adjustScroll() {
        if selectedIndex < scrollOffset {
            scrollOffset = selectedIndex
        } else if selectedIndex >= scrollOffset + maxVisibleCandidates {
            scrollOffset = selectedIndex - maxVisibleCandidates + 1
        }
        // Clamp
        scrollOffset = max(0, scrollOffset)
    }

    func idealSize() -> NSSize {
        let totalCount = candidates.count
        let visibleCount = min(totalCount - scrollOffset, maxVisibleCandidates)
        let height = CGFloat(visibleCount) * rowHeight + auxHeight + padding * 2
        let width: CGFloat = 280
        return NSSize(width: width, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds

        let visibleStart = scrollOffset
        let visibleEnd = min(scrollOffset + maxVisibleCandidates, candidates.count)
        let visibleCount = visibleEnd - visibleStart

        // Draw auxiliary text (what the user typed) at the top
        if !auxiliaryText.isEmpty {
            let auxRect = NSRect(
                x: padding + rowInset,
                y: bounds.height - auxHeight - padding,
                width: bounds.width - padding * 2 - rowInset * 2,
                height: auxHeight
            )
            let auxAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            auxiliaryText.draw(in: auxRect, withAttributes: auxAttrs)
        }

        // Draw scroll-up indicator
        let hasMoreAbove = scrollOffset > 0
        let hasMoreBelow = visibleEnd < candidates.count

        // Draw candidates
        for i in 0..<visibleCount {
            let candidateIndex = scrollOffset + i
            let y = bounds.height - auxHeight - padding - CGFloat(i + 1) * rowHeight
            let rowRect = NSRect(
                x: padding,
                y: y,
                width: bounds.width - padding * 2,
                height: rowHeight
            )

            // Highlight selected row
            if candidateIndex == selectedIndex {
                let highlightPath = NSBezierPath(roundedRect: rowRect, xRadius: rowRadius, yRadius: rowRadius)
                NSColor.selectedContentBackgroundColor.setFill()
                highlightPath.fill()
            }

            let isSelected = candidateIndex == selectedIndex

            let color: NSColor = isSelected ? .alternateSelectedControlTextColor : .labelColor

            // Number label (always shows actual candidate number)
            let numAttrs: [NSAttributedString.Key: Any] = [
                .font: Self.numberFont,
                .foregroundColor: isSelected ? color : NSColor.tertiaryLabelColor
            ]
            drawCentered("\(candidateIndex + 1)", at: padding + rowInset, in: rowRect, height: Self.numberHeight, attrs: numAttrs)

            // Candidate text
            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: Self.candidateFont,
                .foregroundColor: color
            ]
            let wordX = padding + rowInset + 22
            let wordSize = wordSizes[candidateIndex]
            drawCentered(candidates[candidateIndex], at: wordX, in: rowRect, height: wordSize.height, attrs: textAttrs)

            // Dictionary mark right after the word
            if SpellingDictionary.contains(candidates[candidateIndex]), let mark = Self.symbol("checkmark.circle", selected: isSelected) {
                drawIcon(mark, x: wordX + wordSize.width + 6, in: rowRect)
            }

            // Enter hint at the end of the selected row
            if isSelected, let icon = Self.symbol("return", selected: true) {
                drawIcon(icon, x: rowRect.maxX - rowInset - icon.size.width, in: rowRect)
            }
        }

        // Draw scroll indicators (small triangles at edges)
        let indicatorColor = NSColor.tertiaryLabelColor
        if hasMoreAbove {
            let arrowY = bounds.height - auxHeight - padding - 2
            let arrowRect = NSRect(x: bounds.width - arrowInset, y: arrowY - 8, width: 12, height: 8)
            drawArrow(in: arrowRect, up: true, color: indicatorColor)
        }
        if hasMoreBelow {
            let arrowY = bounds.height - auxHeight - padding - CGFloat(visibleCount) * rowHeight + 2
            let arrowRect = NSRect(x: bounds.width - arrowInset, y: arrowY, width: 12, height: 8)
            drawArrow(in: arrowRect, up: false, color: indicatorColor)
        }
    }

    /// Draws `text` at x, vertically centered in `rect` for a line of the given height.
    private func drawCentered(_ text: String, at x: CGFloat, in rect: NSRect, height: CGFloat, attrs: [NSAttributedString.Key: Any]) {
        text.draw(at: NSPoint(x: x, y: rect.midY - height / 2), withAttributes: attrs)
    }

    private func drawIcon(_ icon: NSImage, x: CGFloat, in rect: NSRect) {
        icon.draw(in: NSRect(x: x, y: rect.midY - icon.size.height / 2, width: icon.size.width, height: icon.size.height))
    }

    /// Built once per (symbol, selected): row redraws on every key press reuse them.
    private static var symbolCache: [String: NSImage] = [:]

    private static func symbol(_ name: String, selected: Bool) -> NSImage? {
        let key = "\(name)|\(selected)"
        if let cached = symbolCache[key] { return cached }
        let color: NSColor = selected ? .alternateSelectedControlTextColor : NSColor.labelColor.withAlphaComponent(0.75)
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            .applying(.init(paletteColors: [color]))
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        symbolCache[key] = image
        return image
    }

    /// Filled triangle pointing up or down.
    private func drawArrow(in rect: NSRect, up: Bool, color: NSColor) {
        let tip = up ? rect.maxY : rect.minY
        let base = up ? rect.minY : rect.maxY
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.midX, y: tip))
        path.line(to: NSPoint(x: rect.minX, y: base))
        path.line(to: NSPoint(x: rect.maxX, y: base))
        path.close()
        color.setFill()
        path.fill()
    }

    // MARK: - Mouse handling

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = candidateIndex(at: point) {
            selectedIndex = index
            adjustScroll()
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = candidateIndex(at: point), index == selectedIndex {
            onCandidateClicked?(index)
        }
    }

    /// Returns the candidate index at the given point, or nil if outside candidate rows.
    private func candidateIndex(at point: NSPoint) -> Int? {
        let topOfCandidates = bounds.height - auxHeight - padding
        let clickOffset = topOfCandidates - point.y
        guard clickOffset >= 0 else { return nil }

        let rowIndex = Int(clickOffset / rowHeight)
        // The bottom padding strip would otherwise map to the next, unseen row.
        guard rowIndex < maxVisibleCandidates else { return nil }
        let candidateIndex = scrollOffset + rowIndex
        guard candidateIndex >= 0 && candidateIndex < candidates.count else { return nil }
        return candidateIndex
    }
}
