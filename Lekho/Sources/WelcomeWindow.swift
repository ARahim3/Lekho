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

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupTabs()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupTabs() {
        tabView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            tabView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            tabView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            tabView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])

        let gettingStartedTab = NSTabViewItem(identifier: "start")
        gettingStartedTab.label = "Getting Started"
        gettingStartedTab.view = GettingStartedView()
        tabView.addTabViewItem(gettingStartedTab)

        let layoutTab = NSTabViewItem(identifier: "layout")
        layoutTab.label = "Avro Layout"
        layoutTab.view = LayoutWebView()
        tabView.addTabViewItem(layoutTab)
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
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        let content = buildAttributedContent()
        textView.textStorage?.setAttributedString(content)

        scrollView.documentView = textView
    }

    private func buildAttributedContent() -> NSAttributedString {
        let result = NSMutableAttributedString()

        let titleFont = NSFont.systemFont(ofSize: 22, weight: .bold)
        let headingFont = NSFont.systemFont(ofSize: 15, weight: .semibold)
        let bodyFont = NSFont.systemFont(ofSize: 13, weight: .regular)
        let bodyColor = NSColor.labelColor
        let secondaryColor = NSColor.secondaryLabelColor
        let accentColor = NSColor.controlAccentColor

        result.append(
            NSAttributedString(
                string: "Welcome to Lekho\n",
                attributes: [
                    .font: titleFont, .foregroundColor: bodyColor,
                ]))
        result.append(
            NSAttributedString(
                string: "Avro Phonetic Bengali Keyboard for macOS\n\n",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 14), .foregroundColor: secondaryColor,
                ]))

        result.append(
            NSAttributedString(
                string: "Setup\n",
                attributes: [
                    .font: headingFont, .foregroundColor: accentColor,
                ]))

        let steps = [
            ("1.", "Log out and log back in", "(if you just installed for the first time)"),
            ("2.", "Open System Settings \u{2192} Keyboard \u{2192} Input Sources", ""),
            (
                "3.", "Click  +  \u{2192} search \"Lekho\" \u{2192} select Lekho \u{2192} Add",
                ""
            ),
            ("4.", "Use Globe key or Ctrl+Space to switch input methods", ""),
        ]

        for (num, step, note) in steps {
            result.append(
                NSAttributedString(
                    string: "\n  \(num)  ",
                    attributes: [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .bold),
                        .foregroundColor: accentColor,
                    ]))
            result.append(
                NSAttributedString(
                    string: step,
                    attributes: [
                        .font: bodyFont, .foregroundColor: bodyColor,
                    ]))
            if !note.isEmpty {
                result.append(
                    NSAttributedString(
                        string: "\n        \(note)",
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: secondaryColor,
                        ]))
            }
        }

        result.append(NSAttributedString(string: "\n\n", attributes: [.font: bodyFont]))

        result.append(
            NSAttributedString(
                string: "How to Type\n",
                attributes: [
                    .font: headingFont, .foregroundColor: accentColor,
                ]))

        let tips = [
            ("Type in English phonetically", "e.g.  ami \u{2192} আমি,   bangla \u{2192} বাংলা"),
            ("Space", "commits the top suggestion"),
            ("1-9", "selects a specific candidate from the list"),
            ("Backspace", "deletes the last character"),
            ("Escape", "cancels current input"),
            ("Arrow keys \u{2191}\u{2193}", "navigate through candidates"),
        ]

        for (key, desc) in tips {
            result.append(NSAttributedString(string: "\n  ", attributes: [.font: bodyFont]))
            result.append(
                NSAttributedString(
                    string: key,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                        .foregroundColor: bodyColor,
                    ]))
            result.append(
                NSAttributedString(
                    string: "  \u{2014}  \(desc)",
                    attributes: [
                        .font: bodyFont, .foregroundColor: secondaryColor,
                    ]))
        }

        result.append(NSAttributedString(string: "\n\n", attributes: [.font: bodyFont]))

        result.append(
            NSAttributedString(
                string: "Tip: ",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: secondaryColor,
                ]))
        result.append(
            NSAttributedString(
                string:
                    "You can close this window \u{2014} the keyboard keeps running in the background. Open Lekho again anytime to see this guide.\n\n",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12), .foregroundColor: secondaryColor,
                ]))

        result.append(
            NSAttributedString(
                string: "See the ",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12), .foregroundColor: secondaryColor,
                ]))
        result.append(
            NSAttributedString(
                string: "Avro Layout",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: accentColor,
                ]))
        result.append(
            NSAttributedString(
                string: " tab for the full phonetic key mapping.\n",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12), .foregroundColor: secondaryColor,
                ]))

        // Attribution footer
        result.append(NSAttributedString(string: "\n\n", attributes: [.font: bodyFont]))

        // Separator line
        let separatorParagraph = NSMutableParagraphStyle()
        separatorParagraph.alignment = .center
        result.append(
            NSAttributedString(
                string: "\u{2500}\u{2500}\u{2500}\n\n",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 10),
                    .foregroundColor: NSColor.separatorColor,
                    .paragraphStyle: separatorParagraph,
                ]))

        let footerParagraph = NSMutableParagraphStyle()
        footerParagraph.alignment = .center
        footerParagraph.lineSpacing = 4

        result.append(
            NSAttributedString(
                string: "Developed by ",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: secondaryColor,
                    .paragraphStyle: footerParagraph,
                ]))
        result.append(
            NSAttributedString(
                string: "Abdur Rahim",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: bodyColor,
                    .paragraphStyle: footerParagraph,
                ]))
        result.append(
            NSAttributedString(
                string: "\n",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .paragraphStyle: footerParagraph,
                ]))

        // GitHub link
        let githubURL = URL(string: "https://github.com/ARahim3")!
        result.append(
            NSAttributedString(
                string: "github.com/ARahim3",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: accentColor,
                    .link: githubURL,
                    .paragraphStyle: footerParagraph,
                ]))
        result.append(
            NSAttributedString(
                string: "  \u{00B7}  ",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: secondaryColor,
                    .paragraphStyle: footerParagraph,
                ]))

        // Website link
        let websiteURL = URL(string: "https://arahim3.github.io")!
        result.append(
            NSAttributedString(
                string: "arahim3.github.io",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: accentColor,
                    .link: websiteURL,
                    .paragraphStyle: footerParagraph,
                ]))

        result.append(
            NSAttributedString(
                string: "\nPowered by OpenBangla\u{2019}s riti engine. Built for the Bengali community on macOS.\n",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 10),
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .paragraphStyle: footerParagraph,
                ]))

        return result
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
                body {
                    font-family: -apple-system, "Helvetica Neue", sans-serif;
                    padding: 12px 16px;
                    background: transparent;
                    color-scheme: light dark;
                    color: #333;
                }
                @media (prefers-color-scheme: dark) {
                    body { color: #e0e0e0; }
                    .section-title { color: #6cb4ee; }
                    .key { color: #6cb4ee; }
                    table { border-color: #444; }
                    td { border-color: #3a3a3a; }
                    .bn { color: #e0e0e0; }
                }
                .section-title {
                    color: #007aff;
                    font-size: 12px;
                    font-weight: 600;
                    margin: 10px 0 4px 0;
                    text-transform: none;
                }
                .section-title:first-child { margin-top: 0; }
                table {
                    width: 100%;
                    border-collapse: collapse;
                    margin-bottom: 2px;
                    table-layout: fixed;
                }
                td {
                    padding: 2px 5px;
                    border-bottom: 1px solid #e8e8e8;
                    vertical-align: middle;
                    font-size: 12px;
                    line-height: 1.3;
                }
                .bn {
                    font-size: 15px;
                    font-weight: 500;
                    color: #1a1a1a;
                    width: 32px;
                    text-align: center;
                }
                .key {
                    font-size: 11px;
                    font-weight: 500;
                    color: #007aff;
                    font-family: "SF Mono", Menlo, monospace;
                }
                .pair { width: 25%; }
                .pair-wide { width: 33.33%; }
                .sep { width: 1px; }
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
