import Cocoa
import InputMethodKit

@objc(LekhoInputController)
class LekhoInputController: IMKInputController {

    // MARK: - Engine state

    private var engineCtx: OpaquePointer?
    private var engineConfig: OpaquePointer?
    private var currentSuggestion: OpaquePointer?
    private var selectedIndex: UInt = 0
    private var candidatePanel: CandidatePanel?
    private var lastKnownCursorRect: NSRect = .zero
    /// When true, composedString returns the selected candidate text instead of pre-edit text
    private var showingCandidate: Bool = false

    /// Bengali digits ০-৯ indexed by 0-9
    private static let bengaliDigits: [Character] = [
        "\u{09E6}", "\u{09E7}", "\u{09E8}", "\u{09E9}", "\u{09EA}",
        "\u{09EB}", "\u{09EC}", "\u{09ED}", "\u{09EE}", "\u{09EF}",
    ]

    // MARK: - Lifecycle

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        initializeEngine()
    }

    private func initializeEngine() {
        engineConfig = riti_config_new()

        // Set layout to Avro Phonetic
        "avro_phonetic".withCString { ptr in
            _ = riti_config_set_layout_file(engineConfig, ptr)
        }

        // Set database directory to app bundle's Resources/data
        let dataDir = Bundle.main.resourcePath! + "/data"
        dataDir.withCString { ptr in
            _ = riti_config_set_database_dir(engineConfig, ptr)
        }

        // Set user directory for preferences
        let userDir = getUserDataDir()
        userDir.withCString { ptr in
            _ = riti_config_set_user_dir(engineConfig, ptr)
        }

        // Enable phonetic suggestions
        riti_config_set_phonetic_suggestion(engineConfig, true)
        riti_config_set_suggestion_include_english(engineConfig, true)

        // Create the context
        engineCtx = riti_context_new_with_config(engineConfig)
    }

    private func getUserDataDir() -> String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Lekho")

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(
            at: appSupport,
            withIntermediateDirectories: true
        )

        return appSupport.path
    }

    deinit {
        freeSuggestion()
        if let ctx = engineCtx {
            riti_context_free(ctx)
        }
        if let config = engineConfig {
            riti_config_free(config)
        }
    }

    // MARK: - Key handling

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event,
              event.type == .keyDown,
              let client = sender as? (any IMKTextInput) else {
            return false
        }

        let modifiers = event.modifierFlags

        // Pass through events with Cmd or Ctrl modifiers
        if modifiers.contains(.command) || modifiers.contains(.control) {
            // If there's ongoing input, commit it first
            if riti_context_ongoing_input_session(engineCtx) {
                commitTopCandidate(client: client)
            }
            return false
        }

        let keyCode = event.keyCode

        // Handle Enter/Return - commit current selection
        if keyCode == 36 || keyCode == 76 { // Return or numpad Enter
            if riti_context_ongoing_input_session(engineCtx) {
                commitTopCandidate(client: client)
                return true
            }
            return false
        }

        // Handle Escape - cancel and clear
        if keyCode == 53 {
            if riti_context_ongoing_input_session(engineCtx) {
                riti_context_finish_input_session(engineCtx)
                freeSuggestion()
                client.setMarkedText(
                    "" as NSString,
                    selectionRange: NSRange(location: 0, length: 0),
                    replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
                )
                hideCandidates()
                return true
            }
            return false
        }

        // Handle Backspace
        if keyCode == 51 {
            if riti_context_ongoing_input_session(engineCtx) {
                let ctrlPressed = modifiers.contains(.control)
                freeSuggestion()
                currentSuggestion = riti_context_backspace_event(engineCtx, ctrlPressed)

                if riti_context_ongoing_input_session(engineCtx) {
                    updateMarkedText(client: client)
                    showCandidates(client: client)
                } else {
                    client.setMarkedText(
                        "" as NSString,
                        selectionRange: NSRange(location: 0, length: 0),
                        replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
                    )
                    hideCandidates()
                }
                return true
            }
            return false
        }

        // Handle Space - commit first candidate and insert space
        if keyCode == 49 {
            if riti_context_ongoing_input_session(engineCtx) {
                commitTopCandidate(client: client)
                // Let space pass through to the app
                return false
            }
            return false
        }

        // Handle Tab - commit and pass through
        if keyCode == 48 {
            if riti_context_ongoing_input_session(engineCtx) {
                commitTopCandidate(client: client)
            }
            return false
        }

        // Handle digit keys: if no active session, insert Bengali digit directly
        if !riti_context_ongoing_input_session(engineCtx),
           let chars = event.characters,
           let digit = chars.first,
           digit >= "0" && digit <= "9" {
            let digitValue = Int(String(digit))!
            let bengaliDigit = String(LekhoInputController.bengaliDigits[digitValue])
            client.insertText(
                bengaliDigit as NSString,
                replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
            )
            return true
        }

        // Handle number keys 1-9 for candidate selection (when candidates are showing)
        if riti_context_ongoing_input_session(engineCtx),
           let chars = event.characters,
           let digit = chars.first,
           digit >= "1" && digit <= "9" {
            let index = Int(String(digit))! - 1
            let length = currentSuggestion != nil ? riti_suggestion_get_length(currentSuggestion) : 0
            if index < length {
                commitCandidate(at: index, client: client)
                return true
            }
        }

        // Handle arrow keys for candidate navigation
        if keyCode == 125 { // Down arrow
            if riti_context_ongoing_input_session(engineCtx) {
                let length = currentSuggestion != nil ? riti_suggestion_get_length(currentSuggestion) : 0
                if length > 0 {
                    selectedIndex = (selectedIndex + 1) % UInt(length)
                    showingCandidate = true
                    updateComposition()
                    candidatePanel?.selectCandidate(at: Int(selectedIndex))
                }
                return true
            }
            return false
        }
        if keyCode == 126 { // Up arrow
            if riti_context_ongoing_input_session(engineCtx) {
                let length = currentSuggestion != nil ? riti_suggestion_get_length(currentSuggestion) : 0
                if length > 0 {
                    selectedIndex = selectedIndex == 0 ? UInt(length - 1) : selectedIndex - 1
                    showingCandidate = true
                    updateComposition()
                    candidatePanel?.selectCandidate(at: Int(selectedIndex))
                }
                return true
            }
            return false
        }

        // Handle printable characters - send to riti engine
        guard let characters = event.characters,
              let firstChar = characters.unicodeScalars.first else {
            return false
        }

        let ritiKey = avro_keycode_for_char(firstChar.value)
        if ritiKey == 0 {
            // Unknown character - commit any ongoing input and pass through
            if riti_context_ongoing_input_session(engineCtx) {
                commitTopCandidate(client: client)
            }
            return false
        }

        // Get modifier for riti
        let ritiModifier: UInt8 = modifiers.contains(.shift) ? UInt8(MODIFIER_SHIFT) : 0

        // Get suggestion from engine
        showingCandidate = false
        freeSuggestion()
        currentSuggestion = riti_get_suggestion_for_key(
            engineCtx,
            ritiKey,
            ritiModifier,
            UInt8(selectedIndex)
        )

        if riti_context_ongoing_input_session(engineCtx) {
            updateMarkedText(client: client)
            showCandidates(client: client)
        } else {
            // Engine produced a "lonely" suggestion (single char, punctuation, etc.)
            if let suggestion = currentSuggestion, !riti_suggestion_is_empty(suggestion) {
                if riti_suggestion_is_lonely(suggestion) {
                    let textPtr = riti_suggestion_get_lonely_suggestion(suggestion)
                    if let textPtr = textPtr {
                        let text = String(cString: textPtr)
                        client.insertText(
                            text as NSString,
                            replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
                        )
                        riti_string_free(textPtr)
                    }
                } else {
                    commitTopCandidate(client: client)
                }
            }
            hideCandidates()
        }

        return true
    }

    // MARK: - Text management

    private func updateMarkedText(client: any IMKTextInput) {
        guard let suggestion = currentSuggestion,
              !riti_suggestion_is_empty(suggestion) else {
            return
        }

        // Get the pre-edit text for the currently selected index (bounds-checked)
        let length = riti_suggestion_get_length(suggestion)
        if length == 0 { return }
        let safeIndex = min(selectedIndex, length - 1)
        let preEditPtr = riti_suggestion_get_pre_edit_text(suggestion, safeIndex)
        guard let preEditPtr = preEditPtr else { return }
        let preEditText = String(cString: preEditPtr)
        riti_string_free(preEditPtr)

        // Set as marked (underlined) text
        let attrs: [NSAttributedString.Key: Any] = [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
        ]
        let attrStr = NSAttributedString(string: preEditText, attributes: attrs)

        client.setMarkedText(
            attrStr,
            selectionRange: NSRange(location: preEditText.utf16.count, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
        )
    }

    private func commitTopCandidate(client: any IMKTextInput) {
        commitCandidate(at: Int(selectedIndex), client: client)
    }

    private func commitCandidate(at index: Int, client: any IMKTextInput) {
        guard let suggestion = currentSuggestion,
              !riti_suggestion_is_empty(suggestion) else {
            riti_context_finish_input_session(engineCtx)
            freeSuggestion()
            hideCandidates()
            return
        }

        let text: String
        if riti_suggestion_is_lonely(suggestion) {
            let ptr = riti_suggestion_get_lonely_suggestion(suggestion)
            text = ptr != nil ? String(cString: ptr!) : ""
            if let ptr = ptr { riti_string_free(ptr) }
        } else {
            let length = riti_suggestion_get_length(suggestion)
            let safeIndex = UInt(min(index, Int(length) - 1))
            let ptr = riti_suggestion_get_suggestion(suggestion, safeIndex)
            text = ptr != nil ? String(cString: ptr!) : ""
            if let ptr = ptr { riti_string_free(ptr) }
            riti_context_candidate_committed(engineCtx, safeIndex)
        }

        client.insertText(
            text as NSString,
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
        )

        selectedIndex = 0
        showingCandidate = false
        freeSuggestion()
        hideCandidates()
    }

    // MARK: - Cursor position for candidate window

    /// Get cursor screen rect from the client. Called AFTER updateMarkedText
    /// so that markedRange() returns a valid range.
    private func getCursorRect(client: any IMKTextInput) -> NSRect {
        // Try 1: firstRect with markedRange (most reliable after setMarkedText)
        let marked = client.markedRange()

        if marked.location != NSNotFound {
            let endRange = NSRange(location: marked.location + marked.length, length: 0)
            let rect = client.firstRect(forCharacterRange: endRange, actualRange: nil)
            if isValidCursorRect(rect) {
                lastKnownCursorRect = rect
                return rect
            }

            let rect2 = client.firstRect(forCharacterRange: marked, actualRange: nil)
            if isValidCursorRect(rect2) {
                lastKnownCursorRect = rect2
                return rect2
            }
        }

        // Try 2: firstRect with selectedRange
        let sel = client.selectedRange()
        if sel.location != NSNotFound {
            let rect = client.firstRect(forCharacterRange: sel, actualRange: nil)
            if isValidCursorRect(rect) {
                lastKnownCursorRect = rect
                return rect
            }
        }

        // Try 3: attributes(forCharacterIndex:lineHeightRectangle:)
        for idx in [marked.location, sel.location, 0] {
            guard idx != NSNotFound else { continue }
            var lineRect = NSRect.zero
            client.attributes(forCharacterIndex: idx, lineHeightRectangle: &lineRect)
            if isValidCursorRect(lineRect) {
                lastKnownCursorRect = lineRect
                return lineRect
            }
        }

        // Try 4: Accessibility API fallback (works for Chrome and other apps with broken firstRect)
        if let axRect = getAccessibilityCursorRect(), isValidCursorRect(axRect) {
            lastKnownCursorRect = axRect
            return axRect
        }

        // Try 5: reuse last known good position (from a previous keystroke or app)
        if isValidCursorRect(lastKnownCursorRect) {
            return lastKnownCursorRect
        }

        // Try 6: position near the frontmost window
        let fallback = getFrontWindowFallbackRect()
        lastKnownCursorRect = fallback
        return fallback
    }

    /// Try to get cursor position via the Accessibility API.
    /// Works for Chrome and other apps where IMKTextInput.firstRect returns bad coordinates.
    /// Returns nil if Accessibility permission is not granted or the query fails.
    private func getAccessibilityCursorRect() -> NSRect? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        var focusedValue: AnyObject?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue
        ) == .success else { return nil }

        let focused = focusedValue as! AXUIElement

        // Get selected text range
        var rangeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(
            focused, kAXSelectedTextRangeAttribute as CFString, &rangeValue
        ) == .success else { return nil }

        // Get bounds for the selected text range
        var boundsValue: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            focused, kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue!, &boundsValue
        ) == .success else { return nil }

        var cgRect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &cgRect) else { return nil }

        // Convert CG coordinates (top-left origin) to NS coordinates (bottom-left origin)
        // Use the primary screen height for conversion (screen[0] has menu bar)
        guard let primaryScreenHeight = NSScreen.screens.first?.frame.height else { return nil }
        let nsY = primaryScreenHeight - cgRect.origin.y - cgRect.size.height
        return NSRect(x: cgRect.origin.x, y: nsY, width: cgRect.size.width, height: cgRect.size.height)
    }

    /// Validate that a cursor rect is within the frontmost app's window.
    /// Catches Chrome-like apps that return garbage/uninitialized values.
    private func isValidCursorRect(_ rect: NSRect) -> Bool {
        // Reject garbage/uninitialized memory (subnormal doubles like 1.6e-314)
        if rect.origin.x.isSubnormal || rect.origin.y.isSubnormal ||
           rect.size.width.isSubnormal || rect.size.height.isSubnormal {
            return false
        }

        // Reject zero/near-zero origin (no real cursor sits at the screen corner)
        if rect.origin.x < 1 && rect.origin.y < 1 { return false }

        // Reject zero-height rects (a real cursor line has height > 0)
        if rect.size.height < 1 { return false }

        // Must be within some screen
        let onScreen = NSScreen.screens.contains { $0.frame.contains(rect.origin) }
        if !onScreen { return false }

        // Check if the point is within the frontmost app's windows
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return true }
        let pid = frontApp.processIdentifier
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return true }

        guard let screenHeight = NSScreen.main?.frame.height else { return true }

        for window in windowList {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == pid,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let w = bounds["Width"], w > 50,
                  let h = bounds["Height"], h > 50 else { continue }

            // Convert CG coords (top-left origin) to NS coords (bottom-left origin)
            let winRect = NSRect(
                x: bounds["X"] ?? 0,
                y: screenHeight - (bounds["Y"] ?? 0) - h,
                width: w,
                height: h
            )
            if winRect.contains(rect.origin) {
                return true
            }
        }

        return false
    }

    /// Fallback: position near the top of the frontmost window
    private func getFrontWindowFallbackRect() -> NSRect {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            let m = NSEvent.mouseLocation
            return NSRect(x: m.x, y: m.y - 20, width: 0, height: 20)
        }
        let pid = frontApp.processIdentifier
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]],
              let screenHeight = NSScreen.main?.frame.height else {
            let m = NSEvent.mouseLocation
            return NSRect(x: m.x, y: m.y - 20, width: 0, height: 20)
        }

        for window in windowList {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == pid,
                  let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let w = bounds["Width"], w > 100,
                  let h = bounds["Height"], h > 100 else { continue }

            // Place near the top of the window, slightly indented (where text input usually is)
            let x = (bounds["X"] ?? 0) + 60
            let cgY = (bounds["Y"] ?? 0) + 80  // Below title bar + toolbar area
            let y = screenHeight - cgY
            return NSRect(x: x, y: y, width: 0, height: 20)
        }

        let m = NSEvent.mouseLocation
        return NSRect(x: m.x, y: m.y - 20, width: 0, height: 20)
    }

    // MARK: - Candidate window

    private func showCandidates(client: any IMKTextInput) {
        guard let suggestion = currentSuggestion,
              !riti_suggestion_is_empty(suggestion),
              !riti_suggestion_is_lonely(suggestion) else {
            hideCandidates()
            return
        }

        let length = riti_suggestion_get_length(suggestion)
        var candidates: [String] = []
        for i in 0..<length {
            let ptr = riti_suggestion_get_suggestion(suggestion, i)
            if let ptr = ptr {
                candidates.append(String(cString: ptr))
                riti_string_free(ptr)
            }
        }

        // Get auxiliary text (what the user typed in English)
        let auxPtr = riti_suggestion_get_auxiliary_text(suggestion)
        let auxText = auxPtr != nil ? String(cString: auxPtr!) : ""
        if let auxPtr = auxPtr { riti_string_free(auxPtr) }

        // Get cursor rect AFTER marked text is set (so markedRange is valid)
        let cursorRect = getCursorRect(client: client)

        if candidatePanel == nil {
            candidatePanel = CandidatePanel()
            candidatePanel?.onCandidateSelected = { [weak self] index in
                guard let self = self,
                      let client = self.client() as (any IMKTextInput)? else { return }
                self.commitCandidate(at: index, client: client)
            }
        }

        let prevIndex = riti_suggestion_previously_selected_index(suggestion)
        if prevIndex >= 0 && UInt(prevIndex) < length {
            selectedIndex = UInt(prevIndex)
        } else {
            selectedIndex = 0
        }

        candidatePanel?.show(
            candidates: candidates,
            auxiliaryText: auxText,
            selectedIndex: Int(selectedIndex),
            cursorRect: cursorRect
        )
    }

    private func hideCandidates() {
        candidatePanel?.hide()
    }

    private func freeSuggestion() {
        if let suggestion = currentSuggestion {
            riti_suggestion_free(suggestion)
            currentSuggestion = nil
        }
    }

    // MARK: - Composed string (system queries this for marked text display)

    override func composedString(_ sender: Any!) -> Any! {
        guard let suggestion = currentSuggestion,
              !riti_suggestion_is_empty(suggestion) else {
            return "" as NSString
        }

        let length = riti_suggestion_get_length(suggestion)
        if length == 0 { return "" as NSString }
        let safeIndex = min(selectedIndex, length - 1)

        if showingCandidate {
            // During navigation: show the actual candidate text
            let ptr = riti_suggestion_get_suggestion(suggestion, safeIndex)
            guard let ptr = ptr else { return "" as NSString }
            let text = String(cString: ptr)
            riti_string_free(ptr)
            return text as NSString
        } else {
            // During typing: show the pre-edit text
            let ptr = riti_suggestion_get_pre_edit_text(suggestion, safeIndex)
            guard let ptr = ptr else { return "" as NSString }
            let text = String(cString: ptr)
            riti_string_free(ptr)
            return text as NSString
        }
    }

    // MARK: - Session lifecycle

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        selectedIndex = 0
        freeSuggestion()
    }

    override func deactivateServer(_ sender: Any!) {
        if let client = sender as? (any IMKTextInput),
           riti_context_ongoing_input_session(engineCtx) {
            commitTopCandidate(client: client)
        }
        freeSuggestion()
        hideCandidates()
        super.deactivateServer(sender)
    }

    override func candidates(_ sender: Any!) -> [Any]! {
        guard let suggestion = currentSuggestion,
              !riti_suggestion_is_empty(suggestion) else {
            return []
        }

        let length = riti_suggestion_get_length(suggestion)
        var result: [String] = []
        for i in 0..<length {
            let ptr = riti_suggestion_get_suggestion(suggestion, i)
            if let ptr = ptr {
                result.append(String(cString: ptr))
                riti_string_free(ptr)
            }
        }
        return result
    }
}
