import Foundation

// MARK: - Shared engine

/// Process-wide riti engine shared by every `LekhoInputController`.
///
/// IMK creates one controller per client app, but only one client composes at a
/// time, so a single engine is enough. Sharing it matters for two reasons:
///  - each riti context costs ~2.4 MB and re-parses its embedded JSON on creation;
///  - each context loads the learned-selections file once and rewrites the WHOLE
///    file from its own in-memory copy, so several contexts clobber each other.
///
/// The controller currently composing is the `owner`. Another controller taking
/// over (`claim`) first lets the old owner commit, then ends any stale session.
final class LekhoEngine {
    static let shared = LekhoEngine()

    private(set) var typingMode: LekhoInputController.TypingMode = .phoneticFirst
    private(set) var showEmoji = true
    private(set) weak var owner: LekhoInputController?

    /// Raw phonetic transliteration of the current buffer, from the shadow
    /// context. Only populated in `.phoneticFirst`.
    private(set) var currentPhonetic: String?

    private var mainCtx: OpaquePointer?
    private var mainConfig: OpaquePointer?
    /// Shadow phonetic-only context (`.phoneticFirst` only), fed the same keys in
    /// lockstep so its lonely output is the literal spelling of the buffer.
    private var phoneticCtx: OpaquePointer?
    private var phoneticConfig: OpaquePointer?

    private init() {
        build()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(typingModeChanged),
                           name: .lekhoTypingModeChanged, object: nil)
        center.addObserver(self, selector: #selector(emojiSettingChanged),
                           name: .lekhoEmojiSettingChanged, object: nil)
    }

    // MARK: Ownership

    func isOwner(_ controller: LekhoInputController) -> Bool {
        return owner === controller
    }

    /// Make `controller` the composing owner. If a different controller (or a
    /// deallocated one) left a session behind, it is committed/ended first so the
    /// new client never inherits a stale buffer.
    func claim(_ controller: LekhoInputController) {
        if owner === controller { return }
        owner?.sessionTakenOver()
        finishSession()
        owner = controller
    }

    // MARK: Session

    var hasSession: Bool {
        guard let ctx = mainCtx else { return false }
        return riti_context_ongoing_input_session(ctx)
    }

    /// Feed a key. Returns an owned Suggestion the caller must free.
    /// `selection` is the riti index currently selected (riti preserves it when
    /// the key is a punctuation mark).
    func feed(key: UInt16, modifier: UInt8, selection: UInt8) -> OpaquePointer? {
        let suggestion = riti_get_suggestion_for_key(mainCtx, key, modifier, selection)
        if let ctx = phoneticCtx {
            let shadow = riti_get_suggestion_for_key(ctx, key, modifier, 0)
            currentPhonetic = Self.lonelyText(of: shadow)
            if let shadow = shadow { riti_suggestion_free(shadow) }
        }
        syncShadowSession()
        return suggestion
    }

    /// Backspace. `wholeWord` deletes the entire word being composed.
    /// Returns an owned Suggestion the caller must free.
    func backspace(wholeWord: Bool) -> OpaquePointer? {
        let suggestion = riti_context_backspace_event(mainCtx, wholeWord)
        if let ctx = phoneticCtx {
            let shadow = riti_context_backspace_event(ctx, wholeWord)
            currentPhonetic = Self.lonelyText(of: shadow)
            if let shadow = shadow { riti_suggestion_free(shadow) }
        }
        syncShadowSession()
        return suggestion
    }

    /// End the session after committing the candidate at `ritiIndex`.
    /// Only `.smart` lets riti learn the pick (and write its selections file):
    /// `.phoneticFirst` keeps its own memory (`PhoneticFirstPicks`), because riti
    /// can neither report "nothing remembered" nor learn a pick of index 0.
    func commit(ritiIndex: UInt) {
        if typingMode == .smart {
            riti_context_candidate_committed(mainCtx, ritiIndex)
        }
        finishSession()
    }

    /// End any ongoing session in both contexts. Idempotent.
    func finishSession() {
        if let ctx = mainCtx, riti_context_ongoing_input_session(ctx) {
            riti_context_finish_input_session(ctx)
        }
        if let ctx = phoneticCtx, riti_context_ongoing_input_session(ctx) {
            riti_context_finish_input_session(ctx)
        }
        currentPhonetic = nil
    }

    /// The shadow must never outlive the main session.
    private func syncShadowSession() {
        guard !hasSession else { return }
        if let ctx = phoneticCtx, riti_context_ongoing_input_session(ctx) {
            riti_context_finish_input_session(ctx)
        }
        currentPhonetic = nil
    }

    private static func lonelyText(of suggestion: OpaquePointer?) -> String? {
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

    // MARK: Build / teardown

    private func build() {
        typingMode = LekhoInputController.currentTypingMode()
        showEmoji = LekhoInputController.currentShowEmoji()

        let userDir = Self.userDataDir()
        // riti unwraps the JSON parse of these files; a corrupt one would abort
        // the IME at every launch. Move bad files aside before riti sees them.
        Self.quarantineIfCorrupt(userDir + "/phonetic-candidate-selection.json")
        Self.quarantineIfCorrupt(userDir + "/autocorrect.json")

        // Phonetic-only disables dictionary lookup, autocorrect, and emoji — riti
        // returns a single "lonely" transliteration that is committed inline.
        mainConfig = Self.makeConfig(userDir: userDir, phoneticSuggestion: typingMode != .phoneticOnly)
        mainCtx = riti_context_new_with_config(mainConfig)

        if typingMode == .phoneticFirst {
            phoneticConfig = Self.makeConfig(userDir: userDir, phoneticSuggestion: false)
            phoneticCtx = riti_context_new_with_config(phoneticConfig)
        }
    }

    private func teardown() {
        finishSession()
        if let ctx = mainCtx { riti_context_free(ctx); mainCtx = nil }
        if let cfg = mainConfig { riti_config_free(cfg); mainConfig = nil }
        if let ctx = phoneticCtx { riti_context_free(ctx); phoneticCtx = nil }
        if let cfg = phoneticConfig { riti_config_free(cfg); phoneticConfig = nil }
    }

    /// riti compiles its dictionary, autocorrect, suffix, and emoji data into the
    /// binary, so no database dir is needed — only the user dir.
    private static func makeConfig(userDir: String, phoneticSuggestion: Bool) -> OpaquePointer? {
        let config = riti_config_new()
        "avro_phonetic".withCString { ptr in
            _ = riti_config_set_layout_file(config, ptr)
        }
        userDir.withCString { ptr in
            _ = riti_config_set_user_dir(config, ptr)
        }
        riti_config_set_phonetic_suggestion(config, phoneticSuggestion)
        riti_config_set_suggestion_include_english(config, true)
        return config
    }

    static func userDataDir() -> String {
        // Test/debug hook: keep a scratch run away from the real user data.
        if let override = ProcessInfo.processInfo.environment["LEKHO_USER_DIR"], !override.isEmpty {
            try? FileManager.default.createDirectory(atPath: override, withIntermediateDirectories: true)
            return override
        }
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Lekho")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.path
    }

    /// riti expects a flat `{string: string}` JSON object. Anything else is
    /// renamed out of the way (kept, not deleted, in case the user wants it).
    private static func quarantineIfCorrupt(_ path: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return }
        if let data = fm.contents(atPath: path),
           let object = try? JSONSerialization.jsonObject(with: data),
           object is [String: String] {
            return
        }
        let aside = path + ".corrupt-\(Int(Date().timeIntervalSince1970))"
        NSLog("Lekho: %@ is unreadable, moving it to %@", path, aside)
        try? fm.moveItem(atPath: path, toPath: aside)
    }

    // MARK: Settings changes

    /// Typing mode changed: drop any in-flight word and rebuild the context(s).
    @objc private func typingModeChanged() {
        owner?.engineWillRebuild()
        teardown()
        build()
    }

    /// Emoji is a display-side filter — no rebuild; applies from the next keystroke.
    @objc private func emojiSettingChanged() {
        showEmoji = LekhoInputController.currentShowEmoji()
    }
}

// MARK: - Phonetic-first pick memory

/// Remembers the candidates a user deliberately picked over the literal phonetic
/// spelling in `.phoneticFirst`, keyed by the typed word. Picking the phonetic
/// spelling again forgets the entry. Stored separately from riti's selections
/// so it never alters `.smart` mode's behavior.
final class PhoneticFirstPicks {
    static let shared = PhoneticFirstPicks()

    private var picks: [String: String] = [:]
    private let fileURL: URL
    private let ioQueue = DispatchQueue(label: "com.lekho.inputmethod.picks", qos: .utility)

    /// Characters riti treats as leading/trailing punctuation around a word
    /// (`SplittedString::split`), plus the forms they take in Bangla output.
    private static let affixCharacters = CharacterSet(charactersIn: "-]~!@#%&*()_=+[{}'\";<>/?|.,।“”‘’")

    private init() {
        fileURL = URL(fileURLWithPath: LekhoEngine.userDataDir())
            .appendingPathComponent("phonetic-first-picks.json")
        if let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            picks = stored
        }
    }

    /// The bare word: `"sonar."` → `sonar`, `“সোনার।”` → `সোনার`.
    static func core(_ text: String) -> String {
        return text.trimmingCharacters(in: affixCharacters)
    }

    /// Remembered pick (bare word) for the typed text, if any.
    func pick(forTyped typed: String) -> String? {
        let key = Self.core(typed)
        return key.isEmpty ? nil : picks[key]
    }

    /// Record the outcome of a commit. `phonetic` is the literal-spelling
    /// candidate that was on offer.
    func record(typed: String, chosen: String, phonetic: String) {
        let key = Self.core(typed)
        let chosenCore = Self.core(chosen)
        guard !key.isEmpty, !chosenCore.isEmpty else { return }

        if chosenCore == Self.core(phonetic) {
            guard picks.removeValue(forKey: key) != nil else { return }
        } else {
            // An emoji is a one-off decoration, not a spelling preference.
            guard !LekhoInputController.containsEmoji(chosen),
                  picks[key] != chosenCore else { return }
            picks[key] = chosenCore
        }
        save()
    }

    private func save() {
        let snapshot = picks
        let url = fileURL
        ioQueue.async {
            guard let data = try? JSONSerialization.data(
                withJSONObject: snapshot, options: [.sortedKeys]) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}

extension Notification.Name {
    static let lekhoTypingModeChanged = Notification.Name("LekhoTypingModeChanged")
    static let lekhoEmojiSettingChanged = Notification.Name("LekhoEmojiSettingChanged")
}
