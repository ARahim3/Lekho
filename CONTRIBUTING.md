# Contributing to Lekho

Thanks for your interest. Lekho is a small project with a deliberate direction, and the fastest
way to get something landed is to line up with how it's built. A few notes up front so nobody
wastes an evening:

## Open an issue first (for anything bigger than a bug fix)

Features, new settings, UI changes, icons, build changes: **please open an issue before writing
the code.** There's a planned direction and usually unreleased work sitting on my machine, so a
feature PR can easily land on top of something that's about to ship differently. An issue takes
five minutes and gets you a clear yes / not-now / "here's how it should fit" before you invest.

Small bug fixes with a way to reproduce them don't need an issue.

## What makes a PR easy to work with

- **Small and single-purpose.** One fix or one feature, with the *why* in the description: what
  you typed, what you got, what you expected. Bundles of unrelated changes are very hard to take.
- **Tested in real apps.** Input methods behave differently per app. Say where you tried it
  (TextEdit, Chrome, Word, …). `make test` should pass too.
- **Nothing slow in the typing path.** No IPC, Accessibility, or window-server calls per
  keystroke. That has frozen typing system-wide before.
- **Transliteration and dictionary behavior belong upstream.** Lekho wraps
  [OpenBangla/riti](https://github.com/OpenBangla/riti) and doesn't fork it.

## What to expect from me

- This is a one-person side project next to a day job and other projects, so I can vanish for
  days or weeks at a time. You will get a response, even if it's "not now", once I'm back at it.
  A quiet stretch means busy, not ignored.
- Some PRs will be taken over, rebased, or re-implemented to fit in-flight work. When that happens
  you're credited in the release notes. The idea and the report are the valuable part.
- Fixes usually ship in batches with the next release rather than one by one.

## Reporting issues

Please check these first, they come up a lot and aren't bugs:

- **"Apple could not verify Install Lekho.pkg"**: Lekho isn't signed with a paid Apple Developer
  ID. The [install guide](README.md#install) shows the *Privacy & Security → Open Anyway* step.
  Installing with Homebrew skips that dialog.
- **Lekho doesn't show up in Input Sources**: log out and back in once.
- **Too many suggestions, or emoji you don't want**: Lekho app → **Settings**.

The most useful reports carry: macOS version and chip, the Lekho version (shown in the Lekho
window), the app it happens in, and what you typed **in English letters** → what you got → what
you expected. For crashes or freezes, add the crash report or Console.app filtered by "Lekho".
