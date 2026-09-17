# Lekho (লেখো) — Avro Phonetic Bangla Keyboard for macOS

<div align="center">
  <img src="./docs/preview.png" alt="Lekho Keyboard Banner" width="100%">
</div>

**The only Avro Phonetic keyboard built natively for Apple Silicon Macs.**

Lekho brings Avro Phonetic-style Bangla (Bengali) typing to Apple Silicon Macs natively (M1, M2, M3, M4, M5) — no Rosetta required. If you used Avro Keyboard on Windows, iAvro on macOS, or OpenBangla Keyboard on Linux, Lekho is your native Apple Silicon alternative.

**[Download](https://github.com/ARahim3/Lekho/releases/latest)** | **[Website](https://arahim3.github.io/Lekho/)**

---

## Why Lekho?

The existing Bangla keyboard options for macOS each have limitations on Apple Silicon:

- **Avro Keyboard** (OmicronLab) — Windows-focused, no native macOS build
- **iAvro** — Intel-only macOS build that runs on Apple Silicon through Rosetta. [Apple has announced](https://support.apple.com/en-us/102527) Rosetta support is being wound down — fully available in macOS 27, then limited to legacy games starting in macOS 28. macOS already shows a deprecation warning on Intel-only input methods.
- **OpenBangla Keyboard** — Linux only (Qt-based), no macOS port
- **macOS built-in Bengali** — Apple's own layout, not Avro phonetic

Lekho is built natively for Apple Silicon — no Rosetta required, future-proof as macOS evolves. It works in every app — Safari, Chrome, VS Code, Notes, Spotlight, everywhere.

## Features

- **Avro Phonetic typing** — type `ami banglay gan gai` → আমি বাংলায় গান গাই
- **150k word dictionary** with smart suggestions and autocorrect
- **Smart emoji suggestions** — type কান্না and get 😢, বাংলাদেশ and get 🇧🇩, right in the candidate panel
- **Three typing modes** — *Phonetic-first* (default: your exact spelling by default with the suggestion list still one keypress away), *Smart* (suggestions, autocorrect, and emoji pick the word for you), or *Phonetic-only* (pure character-by-character control, no popup). Switch anytime in Settings.
- **Native Apple Silicon** — ~2.7 MB, instant startup, zero CPU when idle
- **Works on all Apple Silicon Macs** — MacBook Air, MacBook Pro, iMac, Mac Mini, Mac Studio (M1/M2/M3/M4/M5)
- **Works everywhere** — built with Apple's InputMethodKit framework
- **Completely offline** — no internet, no data collection, no telemetry
- **Free and open source** (MPL-2.0) — no ads, no subscription

## Install

### Option A — Homebrew (recommended if you have it)

```sh
brew install --cask arahim3/lekho/lekho
```

That single command auto-taps and installs Lekho. Then jump to **step 3** below to add the input source.

To update later: `brew upgrade --cask lekho`. To uninstall: `brew uninstall --cask lekho`.

### Option B — Download the DMG

1. Download the latest `.dmg` from [Releases](https://github.com/ARahim3/Lekho/releases/latest)
2. Open the DMG and double-click **Install Lekho.pkg**

   > **macOS may block the installer** since Lekho isn't signed with an Apple Developer ID yet. If you see *"Install Lekho.pkg" Not Opened*, follow these two steps:
   >
   > **a.** Click **Done** on the warning dialog (do *not* click "Move to Trash"). The "Open Anyway" option won't appear in System Settings until you do.
   >
   > <img src="./docs/install_blocked_dialog.png" alt="macOS install blocked dialog — click Done" width="500">
   > 
   > **b.** Open **System Settings → Privacy & Security**, scroll to the **Security** section, and click **Open Anyway** next to *"Install Lekho.pkg" was blocked*. Then double-click the .pkg again.
   >
   > <img src="./docs/install_allow_anyway.png" alt="Privacy & Security pane — click Open Anyway" width="500">

### Final steps (both options)

3. Go to **System Settings → Keyboard → Input Sources → Edit**, click **+**, find **Lekho**, and add it
   > If Lekho doesn't appear in the list, log out of your Mac and log back in — macOS sometimes needs this to discover new input methods on first install.
4. Use Globe key or Ctrl+Space to switch to Bangla

## Typing modes

Open the **Settings** tab in the Lekho window to pick how typing behaves:

<p align="center">
  <img src="./docs/settings.png" alt="Lekho Settings tab — Phonetic-first, Smart suggestions, and Phonetic-only modes" width="640">
</p>

- **Phonetic-first** *(default)* — your exact phonetic spelling is committed by default, but the suggestion list is still one keypress away. Lekho remembers the words you deliberately pick.
- **Smart suggestions** — dictionary, autocorrect, and emoji pick the best-matching word when you press space.
- **Phonetic-only** — pure transliteration, no suggestion popup, autocorrect, or emoji.

Changes apply immediately — no restart needed.

## Requirements

- macOS 13 (Ventura) or later
- Apple Silicon Mac (M1/M2/M3/M4/M5)

## Build from Source

Prerequisites: Rust toolchain, Xcode (for Swift and InputMethodKit).

```bash
# Install Rust (if not already)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
rustup target add aarch64-apple-darwin

# Build
make build

# Install to ~/Library/Input Methods/
make install

# Create distributable .dmg
bash scripts/create_dmg.sh
```

## Architecture

```
Swift (InputMethodKit)  ←→  Rust Engine (riti) via C FFI
```

- **Rust engine** (`engine/`) — wraps [OpenBangla/riti](https://github.com/OpenBangla/riti), compiled as a static library
- **Swift IMK layer** (`Lekho/`) — subclasses `IMKInputController`, handles key events, candidate window, and text commits
- **No Xcode project** — built with `swiftc` + `cargo` + shell scripts

## Contributing

Contributions are highly welcome! Whether it's reporting a bug, suggesting a feature, or submitting a pull request to improve the Swift or Rust codebases, feel free to get involved.


## Credits

Lekho is powered by [OpenBangla's riti engine](https://github.com/OpenBangla/riti) — the same Bengali transliteration engine behind [OpenBangla Keyboard](https://github.com/OpenBangla/OpenBangla-Keyboard) on Linux.

## Feedback

Found a bug or have a suggestion? [Open an issue](https://github.com/ARahim3/Lekho/issues).

## License

[MPL-2.0](LICENSE)

---

**Keywords:** Avro keyboard Mac, Bangla keyboard macOS, Bengali typing MacBook, Avro phonetic Apple Silicon, অভ্র কিবোর্ড ম্যাক, বাংলা টাইপিং ম্যাক

Maintained by [Abdur Rahim](https://github.com/ARahim3)
