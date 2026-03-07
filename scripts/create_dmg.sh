#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$PROJECT_ROOT/build/Lekho.app"
PKG_DIR="$PROJECT_ROOT/build/pkg_staging"
DMG_DIR="$PROJECT_ROOT/build/dmg_staging"
VERSION="0.1.0"
PKG_OUTPUT="$PROJECT_ROOT/build/Lekho.pkg"
DMG_OUTPUT="$PROJECT_ROOT/build/Lekho-${VERSION}.dmg"
VOLUME_NAME="Lekho"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: $APP_BUNDLE not found. Run 'make build' first."
    exit 1
fi

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

# Launch the input method as the real user
su "$REAL_USER" -c "open '$INSTALL_DIR/Lekho.app'" 2>/dev/null || true

exit 0
SCRIPT
chmod +x "$PKG_DIR/scripts/postinstall"

echo ">>> Building package..."
# Use --nopayload since we handle installation in postinstall
pkgbuild \
    --nopayload \
    --scripts "$PKG_DIR/scripts" \
    --identifier "com.lekho.inputmethod.Lekho" \
    --version "0.1.0" \
    "$PKG_DIR/Lekho-component.pkg"

# Create a distribution XML for a nicer installer UI
cat > "$PKG_DIR/distribution.xml" << 'DISTXML'
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>Lekho</title>
    <allowed-os-versions><os-version min="13.0"/></allowed-os-versions>
    <options hostArchitectures="arm64" customize="never" require-scripts="false"/>
    <welcome mime-type="text/plain"><![CDATA[
Welcome to Lekho — Avro Phonetic Bengali Keyboard for macOS.

This will install the Avro Phonetic Bengali keyboard to your Mac.

After installation:
  1. Open System Settings → Keyboard → Input Sources
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
             version="0.1.0"
             onConclusion="none">Lekho-component.pkg</pkg-ref>
</installer-gui-script>
DISTXML

echo ">>> Building product package..."
productbuild \
    --distribution "$PKG_DIR/distribution.xml" \
    --package-path "$PKG_DIR" \
    "$PKG_OUTPUT"

echo ">>> Package created: $PKG_OUTPUT"

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

# Clean up staging
rm -rf "$PKG_DIR" "$DMG_DIR"

echo ""
echo "=== Done ==="
echo "DMG: $DMG_OUTPUT ($(du -h "$DMG_OUTPUT" | cut -f1))"
echo "PKG: $PKG_OUTPUT ($(du -h "$PKG_OUTPUT" | cut -f1))"
echo ""
echo "Users just: open DMG → double-click 'Install Lekho.pkg' → done"
