import Cocoa
import InputMethodKit

@objc(LekhoInputController)
class LekhoInputController: IMKInputController {

    // MARK: - Settings

    /// How transliteration and suggestions behave while typing.
    enum TypingMode: String {
        /// Dictionary, autocorrect, and emoji suggestions; the engine's top-ranked
        /// candidate is selected/committed by default. (Original behavior.)
        case smart
        /// The full suggestion list is shown, but the literal phonetic
        /// transliteration is selected/committed by default — unless the user has a
        /// remembered selection for this word. Predictable output, dictionary on tap.
        case phoneticFirst
        /// A single phonetic transliteration committed inline — no candidate popup,
        /// no autocorrect, no emoji.
        case phoneticOnly
    }

    /// UserDefaults key holding the raw value of the current `TypingMode`.
    static let typingModeKey = "LekhoTypingMode"

    /// Legacy bool key (pre-multi-mode). Read only for one-time migration into
    /// `typingModeKey`: true → `.phoneticOnly`, false → `.smart`.
    static let phoneticOnlyModeKey = "LekhoPhoneticOnlyMode"

    /// Resolve the current typing mode, migrating from the legacy bool when the
    /// new key hasn't been written yet. Default (and recommended) is `.phoneticFirst`.
    static func currentTypingMode() -> TypingMode {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: typingModeKey),
           let mode = TypingMode(rawValue: raw) {
            return mode
        }
        // Legacy phonetic-only users keep their setting; everyone else (including
        // upgrades from the old single-toggle build) gets the default.
        if defaults.bool(forKey: phoneticOnlyModeKey) { return .phoneticOnly }
        return .phoneticFirst
    }

    // MARK: - Engine state

    private var engineCtx: OpaquePointer?
    private var engineConfig: OpaquePointer?
    /// Shadow context running phonetic-only, used in `.phoneticFirst` to obtain the
    /// raw transliteration of the current buffer so it can be default-selected in
    /// the main suggestion list. Nil in other modes.
    private var phoneticCtx: OpaquePointer?
    private var phoneticConfig: OpaquePointer?
    /// Raw phonetic transliteration of the current buffer (from `phoneticCtx`).
    private var currentPhonetic: String?
    /// Typing mode captured for the lifetime of the current engine.
    private var typingMode: TypingMode = .smart
    private var currentSuggestion: OpaquePointer?
    private var selectedIndex: UInt = 0
    private var candidatePanel: CandidatePanel?
    private var lastKnownCursorRect: NSRect = .zero

    /// Bengali digits ০-৯ indexed by 0-9
    private static let bengaliDigits: [Character] = [
        "\u{09E6}", "\u{09E7}", "\u{09E8}", "\u{09E9}", "\u{09EA}",
        "\u{09EB}", "\u{09EC}", "\u{09ED}", "\u{09EE}", "\u{09EF}",
    ]

    // MARK: - Lifecycle

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        initializeEngine()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(typingModeChanged),
            name: .lekhoTypingModeChanged,
            object: nil
        )
    }

    private func initializeEngine() {
        typingMode = Self.currentTypingMode()

        // Phonetic-only mode disables dictionary lookup, autocorrect, and emoji
        // suggestions — riti returns a single "lonely" transliteration that the
        // input pipeline commits inline without showing a candidate panel.
        engineConfig = makeConfig(phoneticSuggestion: typingMode != .phoneticOnly)
        engineCtx = riti_context_new_with_config(engineConfig)

        // Phonetic-first runs a second, phonetic-only context in lockstep. Its
        // lonely output gives us the literal transliteration of the current buffer,
        // which we locate in the main suggestion list to select it by default.
        if typingMode == .phoneticFirst {
            phoneticConfig = makeConfig(phoneticSuggestion: false)
            phoneticCtx = riti_context_new_with_config(phoneticConfig)
        }
    }

    /// Build a riti config pointed at the bundle data + user dir, with the given
    /// phonetic-suggestion setting.
    private func makeConfig(phoneticSuggestion: Bool) -> OpaquePointer? {
        let config = riti_config_new()

        // Set layout to Avro Phonetic
        "avro_phonetic".withCString { ptr in
            _ = riti_config_set_layout_file(config, ptr)
        }

        // Set database directory to app bundle's Resources/data
        let dataDir = Bundle.main.resourcePath! + "/data"
        dataDir.withCString { ptr in
            _ = riti_config_set_database_dir(config, ptr)
        }

        // Set user directory for preferences
        let userDir = getUserDataDir()
        userDir.withCString { ptr in
            _ = riti_config_set_user_dir(config, ptr)
        }

        riti_config_set_phonetic_suggestion(config, phoneticSuggestion)
        riti_config_set_suggestion_include_english(config, true)
        return config
    }

    /// Tear down the riti context(s)+config(s) and re-create with current settings.
    /// Called when the typing mode changes; any in-flight session is dropped (host
    /// marked text clears on next keystroke).
    private func rebuildEngine() {
        if let ctx = engineCtx, riti_context_ongoing_input_session(ctx) {
            riti_context_finish_input_session(ctx)
        }
        finishPhoneticShadow()
        freeSuggestion()
        hideCandidates()
        selectedIndex = 0

        if let ctx = engineCtx {
            riti_context_free(ctx)
            engineCtx = nil
        }
        if let cfg = engineConfig {
            riti_config_free(cfg)
            engineConfig = nil
        }
        if let ctx = phoneticCtx {
            riti_context_free(ctx)
            phoneticCtx = nil
        }
        if let cfg = phoneticConfig {
            riti_config_free(cfg)
            phoneticConfig = nil
        }
        initializeEngine()
    }

    @objc private func typingModeChanged() {
        rebuildEngine()
    }

    // MARK: - Phonetic shadow context (.phoneticFirst)

    /// Feed a key to the shadow phonetic-only context and capture the resulting
    /// raw transliteration of the current buffer. No-op outside `.phoneticFirst`.
    private func feedPhoneticShadow(key: UInt16, modifier: UInt8) {
        guard let ctx = phoneticCtx else { return }
        let suggestion = riti_get_suggestion_for_key(ctx, key, modifier, 0)
        currentPhonetic = lonelyText(of: suggestion)
        if let suggestion = suggestion { riti_suggestion_free(suggestion) }
    }

    private func backspacePhoneticShadow(ctrl: Bool) {
        guard let ctx = phoneticCtx else { return }
        let suggestion = riti_context_backspace_event(ctx, ctrl)
        currentPhonetic = lonelyText(of: suggestion)
        if let suggestion = suggestion { riti_suggestion_free(suggestion) }
    }

    /// End any shadow session and clear the cached phonetic text. Idempotent, so
    /// it's safe to call from every session-ending path.
    private func finishPhoneticShadow() {
        if let ctx = phoneticCtx, riti_context_ongoing_input_session(ctx) {
            riti_context_finish_input_session(ctx)
        }
        currentPhonetic = nil
    }

    /// Extract the lonely-suggestion string from a phonetic-only suggestion.
    private func lonelyText(of suggestion: OpaquePointer?) -> String? {
        guard let suggestion = suggestion,
              !riti_suggestion_is_empty(suggestion),
              riti_suggestion_is_lonely(suggestion),
              let ptr = riti_suggestion_get_lonely_suggestion(suggestion) else {
            return nil
        }
        let text = String(cString: ptr)
        riti_string_free(ptr)
        return text
    }

    /// Decide which candidate is selected by default for the current suggestion.
    /// Honors riti's remembered selection first; in `.phoneticFirst` falls back to
    /// the literal phonetic candidate; otherwise index 0.
    private func resolveSelectedIndex() {
        guard let suggestion = currentSuggestion,
              !riti_suggestion_is_empty(suggestion),
              !riti_suggestion_is_lonely(suggestion) else {
            selectedIndex = 0
            return
        }

        let length = riti_suggestion_get_length(suggestion)
        if length == 0 { selectedIndex = 0; return }

        let prevIndex = riti_suggestion_previously_selected_index(suggestion)
        if prevIndex >= 0 && UInt(prevIndex) < length {
            selectedIndex = UInt(prevIndex)
            return
        }

        if typingMode == .phoneticFirst, let phonetic = currentPhonetic {
            for i in 0..<length {
                guard let ptr = riti_suggestion_get_suggestion(suggestion, i) else { continue }
                let candidate = String(cString: ptr)
                riti_string_free(ptr)
                if candidate == phonetic {
                    selectedIndex = i
                    return
                }
            }
        }

        selectedIndex = 0
    }

    /// True when there's an ongoing session AND the suggestion is lonely (riti's
    /// Single variant). In phonetic-only mode every keystroke produces this; in
    /// dictionary mode it should never happen mid-session. Used to bypass
    /// candidate-navigation handlers (Tab, arrows, 1-9) that would otherwise
    /// call get_length on a Single variant and panic.
    private func inLonelySession() -> Bool {
        guard riti_context_ongoing_input_session(engineCtx),
              let suggestion = currentSuggestion,
              !riti_suggestion_is_empty(suggestion) else {
            return false
        }
        return riti_suggestion_is_lonely(suggestion)
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
        NotificationCenter.default.removeObserver(self)
        freeSuggestion()
        if let ctx = engineCtx {
            riti_context_free(ctx)
        }
        if let config = engineConfig {
            riti_config_free(config)
        }
        if let ctx = phoneticCtx {
            riti_context_free(ctx)
        }
        if let config = phoneticConfig {
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
                finishPhoneticShadow()
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
                backspacePhoneticShadow(ctrl: ctrlPressed)

                if riti_context_ongoing_input_session(engineCtx) {
                    resolveSelectedIndex()
                    updateMarkedText(client: client)
                    showCandidates(client: client)
                } else {
                    finishPhoneticShadow()
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

        // Handle Tab - navigate candidates (Shift+Tab cycles backward)
        if keyCode == 48 {
            if riti_context_ongoing_input_session(engineCtx) {
                if inLonelySession() {
                    // Phonetic-only: no candidates to navigate. Commit and let
                    // Tab pass through (indent/focus shift in host app).
                    commitTopCandidate(client: client)
                    return false
                }
                let length = currentSuggestion != nil ? riti_suggestion_get_length(currentSuggestion) : 0
                if length > 0 {
                    if modifiers.contains(.shift) {
                        selectedIndex = selectedIndex == 0 ? UInt(length - 1) : selectedIndex - 1
                    } else {
                        selectedIndex = (selectedIndex + 1) % UInt(length)
                    }
                    updateMarkedText(client: client)
                    candidatePanel?.selectCandidate(at: Int(selectedIndex))
                }
                return true
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
            if inLonelySession() {
                // Phonetic-only: no numbered candidates. Commit pre-edit, then
                // type the digit as a Bengali numeral (matches no-session behavior).
                commitTopCandidate(client: client)
                let digitValue = Int(String(digit))!
                let bengaliDigit = String(LekhoInputController.bengaliDigits[digitValue])
                client.insertText(
                    bengaliDigit as NSString,
                    replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
                )
                return true
            }
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
                if inLonelySession() {
                    // Phonetic-only: commit and let arrow pass through (caret moves).
                    commitTopCandidate(client: client)
                    return false
                }
                let length = currentSuggestion != nil ? riti_suggestion_get_length(currentSuggestion) : 0
                if length > 0 {
                    selectedIndex = (selectedIndex + 1) % UInt(length)
                    updateMarkedText(client: client)
                    candidatePanel?.selectCandidate(at: Int(selectedIndex))
                }
                return true
            }
            return false
        }
        if keyCode == 126 { // Up arrow
            if riti_context_ongoing_input_session(engineCtx) {
                if inLonelySession() {
                    commitTopCandidate(client: client)
                    return false
                }
                let length = currentSuggestion != nil ? riti_suggestion_get_length(currentSuggestion) : 0
                if length > 0 {
                    selectedIndex = selectedIndex == 0 ? UInt(length - 1) : selectedIndex - 1
                    updateMarkedText(client: client)
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
        freeSuggestion()
        currentSuggestion = riti_get_suggestion_for_key(
            engineCtx,
            ritiKey,
            ritiModifier,
            UInt8(selectedIndex)
        )
        feedPhoneticShadow(key: ritiKey, modifier: ritiModifier)

        if riti_context_ongoing_input_session(engineCtx) {
            resolveSelectedIndex()
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
            finishPhoneticShadow()
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

        // riti's Suggestion::len() panics on the Single (lonely) variant — must
        // not call get_length here. get_pre_edit_text(0) handles both variants:
        // for Full it indexes into the list, for Single it returns the lone string.
        let preEditIndex: UInt
        if riti_suggestion_is_lonely(suggestion) {
            preEditIndex = 0
        } else {
            let length = riti_suggestion_get_length(suggestion)
            if length == 0 { return }
            preEditIndex = min(selectedIndex, length - 1)
        }
        let preEditPtr = riti_suggestion_get_pre_edit_text(suggestion, preEditIndex)
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
            finishPhoneticShadow()
            freeSuggestion()
            hideCandidates()
            return
        }

        let text: String
        if riti_suggestion_is_lonely(suggestion) {
            let ptr = riti_suggestion_get_lonely_suggestion(suggestion)
            text = ptr != nil ? String(cString: ptr!) : ""
            if let ptr = ptr { riti_string_free(ptr) }
            // In phonetic-only mode, every keystroke fills riti's buffer. The
            // original lonely path (punctuation outside a session) didn't need
            // a clear because the buffer was empty there — but here we must
            // explicitly end the session or the next keystroke will append to
            // the now-stale buffer.
            riti_context_finish_input_session(engineCtx)
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
        finishPhoneticShadow()
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

        // Try 4: reuse last known good position (from a previous keystroke)
        if lastKnownCursorRect.size.height >= 1 {
            return lastKnownCursorRect
        }

        // Try 5: mouse cursor position (absolute last resort)
        let m = NSEvent.mouseLocation
        let fallback = NSRect(x: m.x, y: m.y - 20, width: 0, height: 20)
        lastKnownCursorRect = fallback
        return fallback
    }

    /// Lightweight validation — no IPC calls, just arithmetic checks.
    /// Catches Chrome/Electron garbage values (subnormal doubles, zero-height rects).
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
        return NSScreen.screens.contains { $0.frame.contains(rect.origin) }
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

        // selectedIndex is resolved by resolveSelectedIndex() before this call;
        // clamp defensively in case the list shrank.
        if selectedIndex >= length { selectedIndex = 0 }

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

    // MARK: - Session lifecycle

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        selectedIndex = 0
        finishPhoneticShadow()
        freeSuggestion()
    }

    override func deactivateServer(_ sender: Any!) {
        if let client = sender as? (any IMKTextInput),
           riti_context_ongoing_input_session(engineCtx) {
            commitTopCandidate(client: client)
        }
        finishPhoneticShadow()
        freeSuggestion()
        hideCandidates()
        super.deactivateServer(sender)
    }

    override func candidates(_ sender: Any!) -> [Any]! {
        // Lonely (Single) suggestions have no candidate list — riti's
        // get_length panics on that variant, so guard before calling it.
        guard let suggestion = currentSuggestion,
              !riti_suggestion_is_empty(suggestion),
              !riti_suggestion_is_lonely(suggestion) else {
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

extension Notification.Name {
    static let lekhoTypingModeChanged = Notification.Name("LekhoTypingModeChanged")
}
