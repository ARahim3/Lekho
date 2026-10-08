#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$PROJECT_ROOT/build/Lekho.app"
PKG_DIR="$PROJECT_ROOT/build/pkg_staging"
DMG_DIR="$PROJECT_ROOT/build/dmg_staging"
VERSION="0.4.2"
VOLUME_NAME="Lekho"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: $APP_BUNDLE not found. Run 'make build' first."
    exit 1
fi

# The installer accepts the architectures the app was built for. arm64 must be
# listed or Apple Silicon Macs are asked to install Rosetta. A universal build
# (make build-universal) is the extra download for Intel Macs, so it gets its
# own name: Lekho-X.Y.Z-Universal.dmg next to the Apple Silicon Lekho-X.Y.Z.dmg.
APP_ARCHS="$(lipo -archs "$APP_BUNDLE/Contents/MacOS/Lekho")"
HOST_ARCHS="$(tr ' ' '\n' <<< "$APP_ARCHS" | sort | paste -sd, -)"
# The installer allows the same minimum macOS as the app (build.sh sets it).
MIN_MACOS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_BUNDLE/Contents/Info.plist")"
SUFFIX=""
[[ " $APP_ARCHS " == *" x86_64 "* ]] && SUFFIX="-Universal"
PKG_OUTPUT="$PROJECT_ROOT/build/Lekho${SUFFIX}.pkg"
DMG_OUTPUT="$PROJECT_ROOT/build/Lekho-${VERSION}${SUFFIX}.dmg"
echo "App architectures: $APP_ARCHS, macOS $MIN_MACOS+"

# Release signing. With a Developer ID Installer certificate in the keychain the
# package and DMG are signed, notarized and stapled; without one they are built
# unsigned, as before. Notarization uses a notarytool keychain profile
# (xcrun notarytool store-credentials "lekho-notary" ...).
#   LEKHO_INSTALLER_IDENTITY  override the installer identity ("-" = unsigned)
#   LEKHO_NOTARY_PROFILE      keychain profile name (default: lekho-notary)
#   LEKHO_SKIP_NOTARIZE=1     sign only, for a quick local packaging check
INSTALLER_IDENTITY="${LEKHO_INSTALLER_IDENTITY:-$(security find-identity -v 2>/dev/null \
    | grep -m1 -o 'Developer ID Installer: [^"]*' || true)}"
[ "$INSTALLER_IDENTITY" = "-" ] && INSTALLER_IDENTITY=""
NOTARY_PROFILE="${LEKHO_NOTARY_PROFILE:-lekho-notary}"
APP_IDENTITY="$(codesign -dvv "$APP_BUNDLE" 2>&1 \
    | sed -n 's/^Authority=\(Developer ID Application: .*\)$/\1/p' || true)"

if [ -n "$INSTALLER_IDENTITY" ] && [ -z "$APP_IDENTITY" ]; then
    echo "Error: $APP_BUNDLE is not Developer ID signed. Run 'make build' first."
    exit 1
fi

# Submit to Apple's notary service, wait, then staple the ticket so Gatekeeper
# can verify offline. notarytool exits 0 even for a rejected submission, so the
# status is checked explicitly and the log is printed on failure.
notarize() {
    local out id
    echo ">>> Notarizing $(basename "$1") (usually a few minutes)..."
    out="$(xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)" || true
    echo "$out"
    if ! grep -q "status: Accepted" <<< "$out"; then
        id="$(sed -n 's/^ *id: //p' <<< "$out" | head -n 1)"
        if [ -n "$id" ]; then
            xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" || true
        fi
        echo "Error: notarization of $1 failed."
        exit 1
    fi
    xcrun stapler staple "$1"
}

echo "=== Creating Installer Package ==="

# Clean up
rm -rf "$PKG_DIR" "$DMG_DIR" "$PKG_OUTPUT"
rm -f "$DMG_OUTPUT"

# --- Step 1: Create the .pkg installer ---

# Payload is empty — we use postinstall to copy the app from a nopayload pkg
# Instead, we embed the app inside the scripts directory so the postinstall
# can copy it to the correct user location.
mkdir -p "$PKG_DIR/scripts"

# Bundle the app inside the scripts dir (pkg scripts can access this)
cp -R "$APP_BUNDLE" "$PKG_DIR/scripts/Lekho.app"

# Preinstall: kill the running instance
cat > "$PKG_DIR/scripts/preinstall" << 'SCRIPT'
#!/bin/bash
# Find the real logged-in user (not root)
REAL_USER=$(stat -f "%Su" /dev/console 2>/dev/null || echo "$USER")
REAL_HOME=$(eval echo "~$REAL_USER")

# Kill running Lekho so the old .app can be replaced
killall Lekho 2>/dev/null || true
# Also kill old AvroBangla instances (from before rename)
killall AvroBangla 2>/dev/null || true
sleep 1

# Remove old installations
rm -rf "$REAL_HOME/Library/Input Methods/Lekho.app" 2>/dev/null || true
rm -rf "$REAL_HOME/Library/Input Methods/AvroBangla.app" 2>/dev/null || true
rm -rf "/Library/Input Methods/Lekho.app" 2>/dev/null || true
rm -rf "/Library/Input Methods/AvroBangla.app" 2>/dev/null || true

exit 0
SCRIPT
chmod +x "$PKG_DIR/scripts/preinstall"

# Postinstall: install to user's ~/Library/Input Methods/
cat > "$PKG_DIR/scripts/postinstall" << 'SCRIPT'
#!/bin/bash
# Find the real logged-in user (not root)
REAL_USER=$(stat -f "%Su" /dev/console 2>/dev/null || echo "$USER")
REAL_HOME=$(eval echo "~$REAL_USER")

INSTALL_DIR="$REAL_HOME/Library/Input Methods"
SCRIPT_DIR="$(dirname "$0")"

# Create install directory
mkdir -p "$INSTALL_DIR"

# Copy the app from the scripts directory
cp -R "$SCRIPT_DIR/Lekho.app" "$INSTALL_DIR/"

# Fix ownership (pkg runs as root, so files would be owned by root)
chown -R "$REAL_USER" "$INSTALL_DIR/Lekho.app"

# Clear quarantine flag
xattr -cr "$INSTALL_DIR/Lekho.app" 2>/dev/null || true

# Place a symlink in /Applications/ so the app shows in Launchpad/Spotlight
rm -f "/Applications/Lekho.app" 2>/dev/null || true
rm -rf "/Applications/Lekho.app" 2>/dev/null || true
ln -sf "$INSTALL_DIR/Lekho.app" "/Applications/Lekho.app"

# Clean up old AvroBangla symlink/app from /Applications/
rm -f "/Applications/AvroBangla.app" 2>/dev/null || true
rm -rf "/Applications/AvroBangla.app" 2>/dev/null || true

# Kill any auto-relaunched old instance (macOS may relaunch the IME
# between preinstall kill and postinstall copy — the old binary runs
# from cache, showing the wrong version)
killall Lekho 2>/dev/null || true
sleep 0.5

# Launch the NEW binary as the real user
su "$REAL_USER" -c "open '$INSTALL_DIR/Lekho.app'" 2>/dev/null || true

# Show an updated menu icon now rather than after the next log out: the input
# menu agent caches icons, and launchd restarts it at once. Wait for macOS to
# rescan Input Methods first (it does so ~2 s after a change).
sleep 4
pkill -x -u "$REAL_USER" TextInputMenuAgent 2>/dev/null || true

exit 0
SCRIPT
chmod +x "$PKG_DIR/scripts/postinstall"

echo ">>> Building package..."
# Use --nopayload since we handle installation in postinstall
pkgbuild \
    --nopayload \
    --scripts "$PKG_DIR/scripts" \
    --identifier "com.lekho.inputmethod.Lekho" \
    --version "0.4.2" \
    "$PKG_DIR/Lekho-component.pkg"

# Create a distribution XML for a nicer installer UI
cat > "$PKG_DIR/distribution.xml" << 'DISTXML'
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>Lekho</title>
    <allowed-os-versions><os-version min="__MIN_MACOS__"/></allowed-os-versions>
    <options hostArchitectures="__HOST_ARCHS__" customize="never" require-scripts="false"/>
    <welcome mime-type="text/plain"><![CDATA[
Welcome to Lekho — Avro Phonetic Bengali Keyboard for macOS.

This will install the Avro Phonetic Bengali keyboard to your Mac.

After installation:
  1. Open __SETTINGS__ → Keyboard → Input Sources
  2. Click + → search "Lekho" → select Lekho → Add
  3. Use Globe key or Ctrl+Space to switch input methods

Note: If this is a fresh install, you may need to log out
and log back in for the keyboard to appear.
    ]]></welcome>
    <choices-outline>
        <line choice="default">
            <line choice="com.lekho.inputmethod.Lekho"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="com.lekho.inputmethod.Lekho" visible="false">
        <pkg-ref id="com.lekho.inputmethod.Lekho"/>
    </choice>
    <pkg-ref id="com.lekho.inputmethod.Lekho"
             version="0.4.2"
             onConclusion="none">Lekho-component.pkg</pkg-ref>
</installer-gui-script>
DISTXML
# Before macOS 13 the Settings app was called System Preferences.
SETTINGS="System Settings"
[ "${MIN_MACOS%%.*}" -lt 13 ] && SETTINGS="System Settings (System Preferences on macOS 11–12)"
sed -i '' -e "s/__HOST_ARCHS__/$HOST_ARCHS/" -e "s/__MIN_MACOS__/$MIN_MACOS/" \
    -e "s/__SETTINGS__/$SETTINGS/" "$PKG_DIR/distribution.xml"

echo ">>> Building product package..."
PRODUCTBUILD_FLAGS=(--distribution "$PKG_DIR/distribution.xml" --package-path "$PKG_DIR")
if [ -n "$INSTALLER_IDENTITY" ]; then
    PRODUCTBUILD_FLAGS+=(--sign "$INSTALLER_IDENTITY" --timestamp)
fi
productbuild "${PRODUCTBUILD_FLAGS[@]}" "$PKG_OUTPUT"

echo ">>> Package created: $PKG_OUTPUT"

# Notarize + staple the package before it goes into the DMG, so the copy users
# run carries its own ticket.
if [ -n "$INSTALLER_IDENTITY" ] && [ "${LEKHO_SKIP_NOTARIZE:-0}" != "1" ]; then
    notarize "$PKG_OUTPUT"
fi

# --- Step 2: Create the DMG ---

echo ""
echo "=== Creating DMG ==="

mkdir -p "$DMG_DIR"
cp "$PKG_OUTPUT" "$DMG_DIR/Install Lekho.pkg"

# Create the DMG
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDZO \
    "$DMG_OUTPUT"

# Sign the DMG itself (a disk image must be signed to be stapled), then notarize it.
if [ -n "$INSTALLER_IDENTITY" ]; then
    echo ">>> Signing DMG ($APP_IDENTITY)..."
    codesign --force --sign "$APP_IDENTITY" --timestamp "$DMG_OUTPUT"
    if [ "${LEKHO_SKIP_NOTARIZE:-0}" != "1" ]; then
        notarize "$DMG_OUTPUT"
    fi
fi

# Clean up staging
rm -rf "$PKG_DIR" "$DMG_DIR"

echo ""
echo "=== Done ==="
echo "DMG: $DMG_OUTPUT ($(du -h "$DMG_OUTPUT" | cut -f1))"
echo "PKG: $PKG_OUTPUT ($(du -h "$PKG_OUTPUT" | cut -f1))"
if [ -n "$INSTALLER_IDENTITY" ] && [ "${LEKHO_SKIP_NOTARIZE:-0}" != "1" ]; then
    echo "Signed, notarized and stapled."
elif [ -n "$INSTALLER_IDENTITY" ]; then
    echo "Signed, NOT notarized (LEKHO_SKIP_NOTARIZE=1)."
else
    echo "Unsigned (no Developer ID Installer certificate in the keychain)."
fi
echo ""
echo "Users just: open DMG → double-click 'Install Lekho.pkg' → done"
