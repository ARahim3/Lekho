---
name: ship
description: Commit and push everything, merge into main, bump the version, tag and publish a GitHub release with the DMG attached, and get back to a working branch. Use only when the user runs /ship.
argument-hint: "[patch|minor|major]"
disable-model-invocation: true
---

# Ship

The user running `/ship` is explicit authorization to commit, merge, tag, push, and publish a GitHub release as described here. Nothing beyond it: never force-push, never rewrite history, never push to `upstream`, only `origin` (`Zibonnn/Lekho`).

**Every ship ends in a release: a `vX.Y.Z` tag with the DMG attached, whatever branch you start on.**

Bump level is the argument (`patch` by default).

## 0. Look first

Run `git status --short`, `git branch --show-current`, and `git fetch origin --tags`. Remember the starting branch as `ORIG`.

## 1. Commit and push everything

Stage **all** changes with `git add -A`, including changes you didn't make (other sessions, other people). Only exception: if a path looks like a secret (`.env*`, `*.pem`, `*.key`, credentials), leave it out and say so.

If anything is staged, commit it. Write a short message in the repo's style (`fix:`, `feat:`, `build:`, `docs:`, `chore:` prefix, imperative, from the actual diff). Follow the session's attribution rules for the trailer. If nothing is staged, skip the commit and continue.

Push `ORIG` to origin (`git push -u origin ORIG` if it has no upstream).

## 2. Get onto up-to-date main

- `ORIG` is not `main`: `git checkout main && git pull origin main`, then `git merge ORIG`.
- `ORIG` is `main`: `git pull origin main`.

On any conflict, stop, leave the repo as is, and tell the user which files conflict. Never resolve silently.

## 3. Release from main

1. **Version.** Latest tag: `git tag --sort=-v:refname | head -1` (`vX.Y.Z`). If `HEAD` already carries a `v*` tag, reuse it and skip the bump and tagging below. Otherwise the new version is the patch (default) / minor / major bump of the latest tag. Set it:
   `/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString X.Y.Z" Lekho/Resources/Info.plist`
2. **Build the DMG before anything is committed or tagged**, so a failed build leaves nothing behind:
   `make build && bash scripts/create_dmg.sh`
   The result is `build/Lekho-X.Y.Z.dmg` (the version comes from `Info.plist`, so the bump must come first). If either step fails, run `git checkout -- Lekho/Resources/Info.plist`, stop, and report the error. Releases are Apple Silicon only; do not use `build-universal`.
3. **Commit and tag.** Commit only `Info.plist` as `release: vX.Y.Z`, then `git tag vX.Y.Z`.
4. **Push.** `git push origin main` then `git push origin vX.Y.Z`.
5. **Publish the release** with the DMG attached (the workflow that bumps the Homebrew cask runs when a release is *published*, and needs the DMG on it):
   ```
   gh release create vX.Y.Z build/Lekho-X.Y.Z.dmg --repo Zibonnn/Lekho --verify-tag \
     --title "Lekho vX.Y.Z" --notes "<notes>"
   ```
   Notes follow the earlier releases: `## What's new` with a few bullets summarizing the commits since the previous tag (`git log <prev-tag>..HEAD --oneline`), then `## Install` saying to open the DMG, double-click **Install Lekho.pkg**, then log out and back in. End with the pull-request/attribution line the session requires.
6. If `HEAD` already had a tag: check `gh release view vX.Y.Z --repo Zibonnn/Lekho --json assets`. If it already has `Lekho-X.Y.Z.dmg`, there is nothing to release; say so. If the release exists without the DMG, `gh release upload vX.Y.Z build/Lekho-X.Y.Z.dmg --repo Zibonnn/Lekho`; if there is no release, create it as above.

## 4. Land on the right branch

- `ORIG` was not `main`: `git checkout ORIG`. (`ORIG` does not need the release commit.)
- `ORIG` was `main`: if `dev` exists locally or on origin, `git checkout dev` and `git pull origin dev`; otherwise `git checkout -b dev`. Then `git merge main` (this brings in the release commit), `git push -u origin dev`, and stay on `dev`. Conflicts: stop and report.

## 5. Report

One short summary: the commit made (or "nothing to commit"), the version and tag, the release URL and DMG size, the branches pushed, the branch you ended on. If any step was skipped or stopped, say which and why.
