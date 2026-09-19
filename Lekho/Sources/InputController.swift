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
        /// Phonetic-only output with the suggestion list underneath: the literal
        /// phonetic transliteration is listed first and committed by default —
        /// unless the user deliberately picked another candidate for this word
        /// before (`PhoneticFirstPicks`).
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

    /// UserDefaults bool key: show emoji candidates in the suggestion list.
    /// Absent means on.
    static let showEmojiKey = "LekhoShowEmoji"

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

    static func currentShowEmoji() -> Bool {
        return UserDefaults.standard.object(forKey: showEmojiKey) as? Bool ?? true
    }

    // MARK: - Session state

    /// The riti engine is shared process-wide; this controller only composes
    /// while it is the engine's owner.
    private let engine = LekhoEngine.shared

    private var currentSuggestion: OpaquePointer?
    /// Candidates as shown to the user. This can differ from riti's list: emoji
    /// may be filtered out, and `.phoneticFirst` lists the literal phonetic
    /// spelling first. `displayOrder[i]` is the riti index of `displayCandidates[i]`.
    private var displayCandidates: [String] = []
    private var displayOrder: [UInt] = []
    /// The literal-spelling candidate when it was found and listed first.
    private var phoneticCandidate: String?
    /// What the user typed (riti's auxiliary text) for the current list.
    private var auxiliaryText = ""
    /// Index into `displayCandidates`.
    private var selectedIndex = 0
    /// The user moved the selection (arrows/Tab) since the last letter key.
    private var userNavigated = false
    private var candidatePanel: CandidatePanel?
    private var lastKnownCursorRect: NSRect = .zero
    /// Last client seen in an IMK callback; fallback for when `client()` is nil.
    private weak var lastClient: (any IMKTextInput)?

    /// Bengali digits ০-৯ indexed by 0-9
    private static let bengaliDigits: [Character] = [
        "\u{09E6}", "\u{09E7}", "\u{09E8}", "\u{09E9}", "\u{09EA}",
        "\u{09EB}", "\u{09EC}", "\u{09ED}", "\u{09EE}", "\u{09EF}",
    ]

    /// Keys after which riti keeps the passed-in selection instead of resetting
    /// it (riti `PhoneticMethod::get_suggestion`).
    private static let selectionPreservingKeys: Set<Character> = [
        ".", "?", "!", ",", ":", ";", "-", "_", ")", "}", "]", "'", "\"",
    ]

    private static let emptyRange = NSRange(location: NSNotFound, length: NSNotFound)

    // MARK: - Candidate helpers

    static func containsEmoji(_ text: String) -> Bool {
        return text.unicodeScalars.contains {
            // isEmoji alone is also true for ASCII digits, '#', and '*'.
            $0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value >= 0x2000)
        }
    }

    /// riti's suggestion list smart-quotes (“ ” ‘ ’) but its phonetic-only output
    /// doesn't; compare the two with quotes straightened.
    private static func straightenQuotes(_ text: String) -> String {
        guard text.contains(where: { "“”‘’".contains($0) }) else { return text }
        return String(text.map { ch -> Character in
            switch ch {
            case "“", "”": return "\""
            case "‘", "’": return "'"
            default: return ch
            }
        })
    }

    /// True when there's an ongoing session AND the suggestion is lonely (riti's
    /// Single variant). In phonetic-only mode every keystroke produces this; in
    /// dictionary mode it should never happen mid-session. Used to bypass
    /// candidate-navigation handlers (Tab, arrows, 1-9).
    private func inLonelySession() -> Bool {
        guard engine.hasSession,
              let suggestion = currentSuggestion,
              !riti_suggestion_is_empty(suggestion) else {
            return false
        }
        return riti_suggestion_is_lonely(suggestion)
    }

    /// riti index of the current selection (0 when there is no list).
    private var selectedRitiIndex: UInt {
        return displayOrder.indices.contains(selectedIndex) ? displayOrder[selectedIndex] : 0
    }

    /// Rebuild the display list from `currentSuggestion` and pick the default
    /// selection. `preserveSelection`: the key was punctuation typed after the
    /// user navigated, so riti's preserved index wins.
    private func refreshCandidates(preserveSelection: Bool) {
        displayCandidates = []
        displayOrder = []
        phoneticCandidate = nil
        auxiliaryText = ""
        selectedIndex = 0

        // riti's Suggestion::len() (and the auxiliary/prev-selection accessors)
        // panic on the Single (lonely) variant — never call them on one.
        guard let suggestion = currentSuggestion,
              !riti_suggestion_is_empty(suggestion),
              !riti_suggestion_is_lonely(suggestion) else {
            return
        }

        var items: [(index: UInt, text: String)] = []
        let length = riti_suggestion_get_length(suggestion)
        for i in 0..<length {
            guard let ptr = riti_suggestion_get_suggestion(suggestion, i) else { continue }
            items.append((i, String(cString: ptr)))
            riti_string_free(ptr)
        }

        if !engine.showEmoji {
            let withoutEmoji = items.filter { !Self.containsEmoji($0.text) }
            if !withoutEmoji.isEmpty { items = withoutEmoji }
        }

        // Phonetic-first: the literal spelling goes on top, suggestions below.
        if engine.typingMode == .phoneticFirst, let phonetic = engine.currentPhonetic {
            let wanted = Self.straightenQuotes(phonetic)
            if let pos = items.firstIndex(where: { Self.straightenQuotes($0.text) == wanted }) {
                let item = items.remove(at: pos)
                items.insert(item, at: 0)
                phoneticCandidate = item.text
            }
        }

        displayCandidates = items.map { $0.text }
        displayOrder = items.map { $0.index }

        if let auxPtr = riti_suggestion_get_auxiliary_text(suggestion) {
            auxiliaryText = String(cString: auxPtr)
            riti_string_free(auxPtr)
        }

        // riti's index is its remembered selection, or the preserved one after a
        // punctuation key. It is 0 — never negative — when nothing is remembered.
        let ritiSelection = riti_suggestion_previously_selected_index(suggestion)
        let ritiDisplayIndex = displayOrder.firstIndex(of: ritiSelection) ?? 0

        if engine.typingMode == .phoneticFirst {
            if preserveSelection {
                selectedIndex = ritiDisplayIndex
            } else if let pick = PhoneticFirstPicks.shared.pick(forTyped: auxiliaryText),
                      let idx = displayCandidates.firstIndex(where: { PhoneticFirstPicks.core($0) == pick }) {
                selectedIndex = idx
            }
        } else {
            selectedIndex = ritiDisplayIndex
        }

        // riti ranks a name-matched emoji above every dictionary word that isn't
        // an exact match (`boish` → 🗺️ first), which would make Space commit an
        // emoji. An emoji is only ever committed by an explicit pick — unless the
        // user typed an emoticon (`:)`), where the emoji is the point.
        let typedWord = PhoneticFirstPicks.core(auxiliaryText)
        if !preserveSelection,
           typedWord.first?.isLetter == true,
           displayCandidates.indices.contains(selectedIndex),
           Self.containsEmoji(displayCandidates[selectedIndex]),
           let firstWord = displayCandidates.firstIndex(where: { !Self.containsEmoji($0) }) {
            selectedIndex = firstWord
        }
    }

    /// Drop all local session state. Does not touch the engine or the client.
    private func resetSessionState() {
        freeSuggestion()
        displayCandidates = []
        displayOrder = []
        phoneticCandidate = nil
        auxiliaryText = ""
        selectedIndex = 0
        userNavigated = false
        hideCandidates()
    }

    private func clearMarkedText(client: any IMKTextInput) {
        client.setMarkedText(
            "" as NSString,
            selectionRange: NSRange(location: 0, length: 0),
            replacementRange: Self.emptyRange
        )
    }

    private func insertBengaliDigit(_ digit: Character, client: any IMKTextInput) {
        let digitValue = Int(String(digit))!
        let bengaliDigit = String(LekhoInputController.bengaliDigits[digitValue])
        client.insertText(bengaliDigit as NSString, replacementRange: Self.emptyRange)
    }

    /// Move the selection by one, wrapping around.
    private func moveSelection(forward: Bool, client: any IMKTextInput) {
        let count = displayCandidates.count
        guard count > 0 else { return }
        if forward {
            selectedIndex = (selectedIndex + 1) % count
        } else {
            selectedIndex = selectedIndex == 0 ? count - 1 : selectedIndex - 1
        }
        userNavigated = true
        // Not updateComposition() — it kills the input session.
        updateMarkedText(client: client)
        candidatePanel?.selectCandidate(at: selectedIndex)
    }

    /// The client to talk to outside of a key event (mouse pick, takeover, …).
    private func currentClient() -> (any IMKTextInput)? {
        return self.client() ?? lastClient
    }

    // MARK: - Engine callbacks

    /// Another controller is taking over the shared engine while this one still
    /// has a word in flight (normally `deactivateServer` has already committed).
    func sessionTakenOver() {
        if engine.hasSession, let client = currentClient() {
            commitTopCandidate(client: client)
        } else {
            resetSessionState()
        }
    }

    /// The typing mode changed; the word being composed is discarded.
    func engineWillRebuild() {
        if engine.hasSession, let client = currentClient() {
            clearMarkedText(client: client)
        }
        resetSessionState()
    }

    deinit {
        freeSuggestion()
    }

    // MARK: - Key handling

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event,
              event.type == .keyDown,
              let client = sender as? (any IMKTextInput) else {
            return false
        }

        lastClient = client
        engine.claim(self)

        let modifiers = event.modifierFlags

        // Pass through events with Cmd or Ctrl modifiers
        if modifiers.contains(.command) || modifiers.contains(.control) {
            // If there's ongoing input, commit it first
            if engine.hasSession {
                commitTopCandidate(client: client)
            }
            return false
        }

        let keyCode = event.keyCode

        // Handle Enter/Return - commit current selection
        if keyCode == 36 || keyCode == 76 { // Return or numpad Enter
            if engine.hasSession {
                commitTopCandidate(client: client)
                return true
            }
            return false
        }

        // Handle Escape - cancel and clear
        if keyCode == 53 {
            if engine.hasSession {
                engine.finishSession()
                clearMarkedText(client: client)
                resetSessionState()
                return true
            }
            return false
        }

        // Handle Backspace (Option+Backspace deletes the whole word being composed)
        if keyCode == 51 {
            if engine.hasSession {
                freeSuggestion()
                currentSuggestion = engine.backspace(wholeWord: modifiers.contains(.option))

                if engine.hasSession {
                    userNavigated = false
                    refreshCandidates(preserveSelection: false)
                    updateMarkedText(client: client)
                    showCandidates(client: client)
                } else {
                    clearMarkedText(client: client)
                    resetSessionState()
                }
                return true
            }
            return false
        }

        // Handle Space - commit the selected candidate, then let the space
        // pass through to the app
        if keyCode == 49 {
            if engine.hasSession {
                commitTopCandidate(client: client)
            }
            return false
        }

        // Handle Tab - navigate candidates (Shift+Tab cycles backward)
        if keyCode == 48 {
            if engine.hasSession {
                if inLonelySession() {
                    // Phonetic-only: no candidates to navigate. Commit and let
                    // Tab pass through (indent/focus shift in host app).
                    commitTopCandidate(client: client)
                    return false
                }
                moveSelection(forward: !modifiers.contains(.shift), client: client)
                return true
            }
            return false
        }

        // Handle digit keys: if no active session, insert Bengali digit directly
        if !engine.hasSession,
           let digit = event.characters?.first,
           digit >= "0" && digit <= "9" {
            insertBengaliDigit(digit, client: client)
            return true
        }

        // Handle number keys 1-9 for candidate selection (when candidates are showing)
        if engine.hasSession,
           let digit = event.characters?.first,
           digit >= "1" && digit <= "9" {
            if inLonelySession() {
                // Phonetic-only: no numbered candidates. Commit pre-edit, then
                // type the digit as a Bengali numeral (matches no-session behavior).
                commitTopCandidate(client: client)
                insertBengaliDigit(digit, client: client)
                return true
            }
            let index = Int(String(digit))! - 1
            if index < displayCandidates.count {
                commitCandidate(at: index, client: client)
                return true
            }
        }

        // Handle arrow keys for candidate navigation
        if keyCode == 125 || keyCode == 126 { // Down / Up arrow
            if engine.hasSession {
                if inLonelySession() {
                    // Phonetic-only: commit and let arrow pass through (caret moves).
                    commitTopCandidate(client: client)
                    return false
                }
                moveSelection(forward: keyCode == 125, client: client)
                return true
            }
            return false
        }

        // Handle printable characters - send to riti engine
        guard let firstChar = event.characters?.unicodeScalars.first else {
            return false
        }

        let ritiKey = avro_keycode_for_char(firstChar.value)
        if ritiKey == 0 {
            // Unknown character - commit any ongoing input and pass through
            if engine.hasSession {
                commitTopCandidate(client: client)
            }
            return false
        }

        // Get modifier for riti
        let ritiModifier: UInt8 = modifiers.contains(.shift) ? UInt8(MODIFIER_SHIFT) : 0

        // A selection the user navigated to survives a punctuation key (riti
        // keeps the index we pass in); any other key resets it.
        let preserveSelection = engine.hasSession && userNavigated
            && Self.selectionPreservingKeys.contains(Character(firstChar))
        let passedSelection = UInt8(clamping: selectedRitiIndex)

        // Get suggestion from engine
        freeSuggestion()
        currentSuggestion = engine.feed(key: ritiKey, modifier: ritiModifier, selection: passedSelection)

        if engine.hasSession {
            if !preserveSelection { userNavigated = false }
            refreshCandidates(preserveSelection: preserveSelection)
            updateMarkedText(client: client)
            showCandidates(client: client)
        } else {
            // Engine produced a "lonely" suggestion (single char, punctuation, etc.)
            if let suggestion = currentSuggestion, !riti_suggestion_is_empty(suggestion) {
                if riti_suggestion_is_lonely(suggestion) {
                    if let textPtr = riti_suggestion_get_lonely_suggestion(suggestion) {
                        let text = String(cString: textPtr)
                        riti_string_free(textPtr)
                        client.insertText(text as NSString, replacementRange: Self.emptyRange)
                    }
                } else {
                    refreshCandidates(preserveSelection: false)
                    commitTopCandidate(client: client)
                }
            }
            engine.finishSession()
            resetSessionState()
        }

        return true
    }

    // MARK: - Text management

    private func updateMarkedText(client: any IMKTextInput) {
        guard let suggestion = currentSuggestion,
              !riti_suggestion_is_empty(suggestion) else {
            return
        }

        // get_pre_edit_text handles both variants: for Full it indexes into the
        // list, for Single (lonely) it returns the lone string.
        let preEditIndex: UInt
        if riti_suggestion_is_lonely(suggestion) {
            preEditIndex = 0
        } else {
            if displayOrder.isEmpty { return }
            preEditIndex = selectedRitiIndex
        }
        guard let preEditPtr = riti_suggestion_get_pre_edit_text(suggestion, preEditIndex) else { return }
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
            replacementRange: Self.emptyRange
        )
    }

    private func commitTopCandidate(client: any IMKTextInput) {
        commitCandidate(at: selectedIndex, client: client)
    }

    /// Commit the candidate at display index `index` and end the session.
    private func commitCandidate(at index: Int, client: any IMKTextInput) {
        guard let suggestion = currentSuggestion,
              !riti_suggestion_is_empty(suggestion) else {
            engine.finishSession()
            resetSessionState()
            return
        }

        let text: String
        if riti_suggestion_is_lonely(suggestion) {
            // Phonetic-only: every keystroke fills riti's buffer, so the session
            // must be ended explicitly or the next key appends to a stale buffer.
            let ptr = riti_suggestion_get_lonely_suggestion(suggestion)
            text = ptr != nil ? String(cString: ptr!) : ""
            if let ptr = ptr { riti_string_free(ptr) }
            engine.finishSession()
        } else if displayCandidates.isEmpty {
            text = ""
            engine.finishSession()
        } else {
            let safeIndex = min(max(index, 0), displayCandidates.count - 1)
            text = displayCandidates[safeIndex]
            if engine.typingMode == .phoneticFirst, let phonetic = phoneticCandidate {
                PhoneticFirstPicks.shared.record(typed: auxiliaryText, chosen: text, phonetic: phonetic)
            }
            engine.commit(ritiIndex: displayOrder[safeIndex])
        }

        client.insertText(text as NSString, replacementRange: Self.emptyRange)
        resetSessionState()
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
        guard !displayCandidates.isEmpty else {
            hideCandidates()
            return
        }

        // Get cursor rect AFTER marked text is set (so markedRange is valid)
        let cursorRect = getCursorRect(client: client)

        if candidatePanel == nil {
            candidatePanel = CandidatePanel()
            candidatePanel?.onCandidateSelected = { [weak self] index in
                guard let self = self,
                      self.engine.isOwner(self),
                      let client = self.currentClient() else { return }
                self.commitCandidate(at: index, client: client)
            }
        }

        candidatePanel?.show(
            candidates: displayCandidates,
            auxiliaryText: auxiliaryText,
            selectedIndex: selectedIndex,
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
        engine.claim(self)
        // Nothing can legitimately be in flight for a client that is only now
        // becoming active; clear any leftovers in both engine and controller.
        engine.finishSession()
        resetSessionState()
    }

    override func deactivateServer(_ sender: Any!) {
        commitOrReset(sender)
        super.deactivateServer(sender)
    }

    /// The client asks for the composition to end — e.g. the user clicked
    /// elsewhere in the text mid-word. Without this the engine would keep the old
    /// buffer and prepend it to whatever is typed at the new location.
    override func commitComposition(_ sender: Any!) {
        commitOrReset(sender)
    }

    private func commitOrReset(_ sender: Any!) {
        if engine.isOwner(self), engine.hasSession {
            if let client = (sender as? (any IMKTextInput)) ?? currentClient() {
                commitTopCandidate(client: client)
                return
            }
            engine.finishSession()
        }
        resetSessionState()
    }

    override func candidates(_ sender: Any!) -> [Any]! {
        return displayCandidates
    }
}
