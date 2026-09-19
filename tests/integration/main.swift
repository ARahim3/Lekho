import Cocoa
import InputMethodKit

// Headless integration test: drives the real LekhoInputController with
// synthesized key events against a mock IMKTextInput client.

final class MockClient: NSObject, IMKTextInput {
    var committed = ""
    var marked = ""

    func insertText(_ string: Any!, replacementRange: NSRange) {
        committed += (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        marked = ""
    }
    func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {
        marked = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
    }
    func selectedRange() -> NSRange { NSRange(location: committed.utf16.count, length: 0) }
    func markedRange() -> NSRange {
        marked.isEmpty ? NSRange(location: NSNotFound, length: 0)
                       : NSRange(location: committed.utf16.count, length: marked.utf16.count)
    }
    func attributedSubstring(from range: NSRange) -> NSAttributedString! { NSAttributedString(string: "") }
    func length() -> Int { committed.utf16.count + marked.utf16.count }
    func characterIndex(for point: NSPoint, tracking: IMKLocationToOffsetMappingMode,
                        inMarkedRange: UnsafeMutablePointer<ObjCBool>!) -> Int { 0 }
    func attributes(forCharacterIndex index: Int,
                    lineHeightRectangle lineRect: UnsafeMutablePointer<NSRect>!) -> [AnyHashable: Any]! {
        lineRect?.pointee = NSRect(x: 40, y: 40, width: 1, height: 18); return [:]
    }
    func validAttributesForMarkedText() -> [Any]! { [] }
    func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String!) {}
    func selectMode(_ modeIdentifier: String!) {}
    func supportsUnicode() -> Bool { true }
    func bundleIdentifier() -> String! { "test.client" }
    func windowLevel() -> CGWindowLevel { 0 }
    func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { false }
    func uniqueClientIdentifierString() -> String! { "test" }
    func string(from range: NSRange, actualRange: NSRangePointer!) -> String! { "" }
    func firstRect(forCharacterRange aRange: NSRange, actualRange: NSRangePointer!) -> NSRect {
        NSRect(x: 40, y: 40, width: 1, height: 18)
    }
}

var failures = 0
func check(_ name: String, _ got: String, _ want: String) {
    if got == want { print("  ok   \(name): \(got)") }
    else { failures += 1; print("  FAIL \(name): got «\(got)» want «\(want)»") }
}
func checkTrue(_ name: String, _ cond: Bool, _ detail: String = "") {
    if cond { print("  ok   \(name) \(detail)") } else { failures += 1; print("  FAIL \(name) \(detail)") }
}

let SPACE: UInt16 = 49, RET: UInt16 = 36, BKSP: UInt16 = 51, TAB: UInt16 = 48
let DOWN: UInt16 = 125, UP: UInt16 = 126, ESC: UInt16 = 53

struct Rig {
    let controller: LekhoInputController
    let client = MockClient()
    init() { controller = LekhoInputController(server: nil, delegate: nil, client: nil) }

    func key(_ code: UInt16, chars: String = "", flags: NSEvent.ModifierFlags = []) {
        let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                  windowNumber: 0, context: nil, characters: chars,
                                  charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
        let handled = controller.handle(ev, client: client)
        if code == SPACE && !handled { client.committed += " " }  // space passes through to the app
    }
    func type(_ text: String) {
        for ch in text {
            if ch == " " { key(SPACE, chars: " ") }
            else { key(0, chars: String(ch), flags: ch.isUppercase ? .shift : []) }
        }
    }
    var candidates: [String] { (controller.candidates(client) as? [String]) ?? [] }
    func take() -> String { let s = client.committed; client.committed = ""; return s }
}

func setMode(_ mode: String) {
    UserDefaults.standard.set(mode, forKey: LekhoInputController.typingModeKey)
    NotificationCenter.default.post(name: .lekhoTypingModeChanged, object: nil)
}
func setEmoji(_ on: Bool) {
    UserDefaults.standard.set(on, forKey: LekhoInputController.showEmojiKey)
    NotificationCenter.default.post(name: .lekhoEmojiSettingChanged, object: nil)
}

// --- setup: scratch user dir with a deliberately corrupt riti selections file
let userDir = ProcessInfo.processInfo.environment["LEKHO_USER_DIR"]!
try? FileManager.default.removeItem(atPath: userDir)
try! FileManager.default.createDirectory(atPath: userDir, withIntermediateDirectories: true)
try! "{ this is not json".write(toFile: userDir + "/phonetic-candidate-selection.json", atomically: true, encoding: .utf8)
UserDefaults.standard.set("phoneticFirst", forKey: LekhoInputController.typingModeKey)
UserDefaults.standard.set(true, forKey: LekhoInputController.showEmojiKey)

let a = Rig()

print("== corrupt selections file is quarantined, not fatal")
a.type("ami ")
check("survived + typed", a.take(), "আমি ")
let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: userDir)) ?? []
checkTrue("moved aside", leftovers.contains { $0.contains(".corrupt-") }, "\(leftovers)")

print("== phonetic-first: literal spelling is listed first and committed")
for (typed, want) in [("sonar", "সনার"), ("hasi", "হাসি"), ("academy", "আচাদেম্য"),
                      ("sonargulo", "সনারগুল"), (":)", "ঃ)"), ("ami", "আমি")] {
    a.type(typed)
    check("\(typed) → row 1", a.candidates.first ?? "", want)
    a.type(" ")
    check("\(typed) + space", a.take(), want + " ")
}
a.type("sonar"); checkTrue("suggestions still listed below", a.candidates.contains("সোনার"), "\(a.candidates)")
a.key(ESC); _ = a.take()
a.type("\"ami\""); check("quoted word selects literal spelling", a.client.marked, "“আমি”")
a.type(" "); check("quoted word commit", a.take(), "“আমি” ")

print("== phonetic-first: deliberate picks are remembered, re-picking phonetic forgets")
a.type("sonar"); a.key(DOWN); a.type(" ")
check("pick via arrow", a.take(), "সোনার ")
a.type("sonar ");  check("remembered next time", a.take(), "সোনার ")
a.type("sonar. "); check("remembered with punctuation", a.take(), "সোনার। ")
a.type("sonar"); check("phonetic still row 1", a.candidates.first ?? "", "সনার")
a.key(UP); a.type(" "); check("re-pick phonetic", a.take(), "সনার ")
a.type("sonar ");  check("forgotten again", a.take(), "সনার ")
// riti itself can never learn a pick of ITS index 0 (হাঁসই for hasi) — ours can.
a.type("hasi"); checkTrue("riti's top word is row 2", a.candidates.count > 1 && a.candidates[1] == "হাঁসই", "\(a.candidates.prefix(3))")
a.key(0, chars: "2"); check("pick by number", a.take(), "হাঁসই")
a.type("hasi ");   check("riti-index-0 pick remembered", a.take(), "হাঁসই ")
a.type("love"); let heart = a.candidates.firstIndex { LekhoInputController.containsEmoji($0) }!
a.key(0, chars: String(heart + 1)); _ = a.take()
a.type("love ");   check("emoji pick is NOT remembered", a.take(), "লভে ")
checkTrue("riti selections file untouched in this mode",
          !FileManager.default.fileExists(atPath: userDir + "/phonetic-candidate-selection.json"))

print("== navigation + punctuation keeps the navigated selection")
a.type("bari"); a.key(DOWN); a.key(DOWN); let navigated = a.candidates[2]
a.type(","); check("selection survives ','", a.client.marked, navigated + ",")
a.type(" "); _ = a.take()
a.type("bari"); a.key(DOWN); a.key(BKSP); check("backspace resets to literal", a.client.marked, "বার")
a.key(ESC); checkTrue("escape clears", a.client.marked.isEmpty && a.take().isEmpty)

print("== emoji toggle")
a.type("fire"); checkTrue("emoji shown when on", a.candidates.contains { LekhoInputController.containsEmoji($0) }, "\(a.candidates)")
a.key(ESC); setEmoji(false)
a.type("fire"); checkTrue("emoji hidden when off", !a.candidates.contains { LekhoInputController.containsEmoji($0) }, "\(a.candidates)")
a.key(ESC)
a.type(":)"); checkTrue("emoticon list has no emoji", !a.candidates.contains { LekhoInputController.containsEmoji($0) }, "\(a.candidates)")
a.key(ESC); _ = a.take()

print("== smart mode (emoji off): index mapping + riti learning")
setMode("smart")
a.type("sonar "); check("smart commits top-ranked", a.take(), "সোনার ")
a.type("fire"); let smartList = a.candidates
checkTrue("no emoji in smart list", !smartList.contains { LekhoInputController.containsEmoji($0) }, "\(smartList)")
a.key(0, chars: "2"); check("number key picks displayed row 2", a.take(), smartList[1])
a.type("fire "); check("riti learned that row (mapped index)", a.take(), smartList[1] + " ")
setEmoji(true)
a.type("boish"); checkTrue("riti ranks an emoji first here", LekhoInputController.containsEmoji(a.candidates[0]), "\(a.candidates.prefix(3))")
a.type(" "); check("…but space never commits an emoji", a.take(), "বিশ ")
a.type(":) "); check("emoticon still gives its emoji", a.take(), "😃 ")
a.type("fire"); checkTrue("emoji back", a.candidates.contains("🔥")); check("learned pick still selected", a.client.marked, smartList[1])
a.key(ESC); _ = a.take()

print("== phonetic-only")
setMode("phoneticOnly")
a.type("sonar"); checkTrue("no candidate list", a.candidates.isEmpty)
a.type(" "); check("inline literal", a.take(), "সনার ")
a.type("ami"); a.key(0, chars: "2"); check("digit commits + bengali digit", a.take(), "আমি২")
a.type("ami"); a.key(TAB); check("tab commits (lonely guard)", a.take(), "আমি")

print("== option+backspace deletes the whole word")
setMode("phoneticFirst")
a.type("sonar"); a.key(BKSP, flags: .option)
checkTrue("word gone", a.client.marked.isEmpty && a.take().isEmpty)
a.type("ami "); check("clean next word", a.take(), "আমি ")
a.key(0, chars: "7"); check("bengali digit outside session", a.take(), "৭")

print("== commitComposition (click elsewhere mid-word)")
a.type("ami"); a.controller.commitComposition(a.client)
check("word committed", a.take(), "আমি")
a.type("t "); check("no stale buffer", a.take(), "ত ")

print("== shared engine: second client takes over mid-word")
let b = Rig()
a.type("ami")
b.type("t ")
check("first client got its word", a.take(), "আমি")
check("second client starts clean", b.take(), "ত ")
a.type("tumi"); b.controller.activateServer(b.client)
check("activate elsewhere commits the old word", a.take(), "তুমি")
a.type("ki"); a.controller.deactivateServer(a.client); check("deactivate commits", a.take(), "কি")

print("== live mode switch mid-word drops the word")
a.type("sonar"); setMode("smart")
checkTrue("dropped", a.client.marked.isEmpty && a.take().isEmpty)
a.type("sonar "); check("new mode active", a.take(), "সোনার ")

UserDefaults.standard.removePersistentDomain(forName: ProcessInfo.processInfo.processName)
print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
