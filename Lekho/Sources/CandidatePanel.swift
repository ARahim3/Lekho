import Cocoa

class CandidatePanel {
    private var panel: NSPanel?
    private var contentView: CandidateView?

    func show(candidates: [String], auxiliaryText: String, selectedIndex: Int, cursorRect: NSRect) {
        if panel == nil {
            createPanel()
        }

        guard let panel = panel, let contentView = contentView else { return }

        contentView.update(candidates: candidates, auxiliaryText: auxiliaryText, selectedIndex: selectedIndex)

        // Size the panel to fit content
        let size = contentView.idealSize()
        panel.setContentSize(size)

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

        panel.setFrameOrigin(origin)
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
        panel.contentView = contentView

        self.panel = panel
        self.contentView = contentView
    }
}

// MARK: - CandidateView

class CandidateView: NSView {
    private var candidates: [String] = []
    private var auxiliaryText: String = ""
    private var selectedIndex: Int = 0
    private var scrollOffset: Int = 0

    private let padding: CGFloat = 6
    private let rowHeight: CGFloat = 24
    private let auxHeight: CGFloat = 20
    private let maxVisibleCandidates = 9

    func update(candidates: [String], auxiliaryText: String, selectedIndex: Int) {
        self.candidates = candidates
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

        // Background
        let bgPath = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        NSColor.windowBackgroundColor.setFill()
        bgPath.fill()

        // Border
        NSColor.separatorColor.setStroke()
        bgPath.lineWidth = 0.5
        bgPath.stroke()

        let visibleStart = scrollOffset
        let visibleEnd = min(scrollOffset + maxVisibleCandidates, candidates.count)
        let visibleCount = visibleEnd - visibleStart

        // Draw auxiliary text (what the user typed) at the top
        if !auxiliaryText.isEmpty {
            let auxRect = NSRect(
                x: padding + 4,
                y: bounds.height - auxHeight - padding,
                width: bounds.width - padding * 2 - 8,
                height: auxHeight
            )
            let auxAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .regular),
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
                let highlightPath = NSBezierPath(roundedRect: rowRect, xRadius: 4, yRadius: 4)
                NSColor.selectedContentBackgroundColor.setFill()
                highlightPath.fill()
            }

            let isSelected = candidateIndex == selectedIndex

            // Number label (always shows actual candidate number)
            let numRect = NSRect(x: padding + 4, y: y + 2, width: 22, height: rowHeight - 4)
            let numAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: isSelected
                    ? NSColor.alternateSelectedControlTextColor
                    : NSColor.tertiaryLabelColor
            ]
            "\(candidateIndex + 1)".draw(in: numRect, withAttributes: numAttrs)

            // Candidate text
            let textRect = NSRect(
                x: padding + 28,
                y: y + 2,
                width: bounds.width - padding * 2 - 32,
                height: rowHeight - 4
            )
            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 16),
                .foregroundColor: isSelected
                    ? NSColor.alternateSelectedControlTextColor
                    : NSColor.labelColor
            ]
            candidates[candidateIndex].draw(in: textRect, withAttributes: textAttrs)
        }

        // Draw scroll indicators (small triangles at edges)
        let indicatorColor = NSColor.tertiaryLabelColor
        if hasMoreAbove {
            let arrowY = bounds.height - auxHeight - padding - 2
            let arrowRect = NSRect(x: bounds.width - 20, y: arrowY - 8, width: 12, height: 8)
            drawUpArrow(in: arrowRect, color: indicatorColor)
        }
        if hasMoreBelow {
            let arrowY = bounds.height - auxHeight - padding - CGFloat(visibleCount) * rowHeight + 2
            let arrowRect = NSRect(x: bounds.width - 20, y: arrowY, width: 12, height: 8)
            drawDownArrow(in: arrowRect, color: indicatorColor)
        }
    }

    private func drawUpArrow(in rect: NSRect, color: NSColor) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.midX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        path.close()
        color.setFill()
        path.fill()
    }

    private func drawDownArrow(in rect: NSRect, color: NSColor) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.midX, y: rect.minY))
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path.close()
        color.setFill()
        path.fill()
    }
}
