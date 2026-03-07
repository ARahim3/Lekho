#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Lekho"
APP_BUNDLE="$PROJECT_ROOT/build/$APP_NAME.app"
INSTALL_DIR="$HOME/Library/Input Methods"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: $APP_BUNDLE not found. Run ./scripts/build.sh first."
    exit 1
fi

echo "=== Installing $APP_NAME ==="

# Kill existing instance if running
killall "$APP_NAME" 2>/dev/null || true
killall "AvroBangla" 2>/dev/null || true  # old name
sleep 1

# Create install directory if needed
mkdir -p "$INSTALL_DIR"

# Remove old installation (including old AvroBangla name)
rm -rf "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null || true
rm -rf "$INSTALL_DIR/AvroBangla.app" 2>/dev/null || true
rm -f "/Applications/AvroBangla.app" 2>/dev/null || true

# Copy new build
echo ">>> Copying $APP_NAME.app to $INSTALL_DIR/..."
cp -R "$APP_BUNDLE" "$INSTALL_DIR/"

# Clear extended attributes
xattr -cr "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null || true

# Place a symlink in /Applications/ so the app shows in Launchpad/Spotlight
rm -f "/Applications/$APP_NAME.app" 2>/dev/null || true
rm -rf "/Applications/$APP_NAME.app" 2>/dev/null || true
ln -sf "$INSTALL_DIR/$APP_NAME.app" "/Applications/$APP_NAME.app" 2>/dev/null || true

# Relaunch the app so it's running in background
echo ">>> Launching $APP_NAME..."
open "$INSTALL_DIR/$APP_NAME.app"

echo ""
echo "=== Installation complete ==="
echo ""
echo "If this is a first-time install:"
echo "  1. Log out and log back in"
echo "  2. Go to System Settings → Keyboard → Input Sources"
echo "  3. Click '+' → search for 'Lekho' → select 'Lekho'"
echo "  4. Use Ctrl+Space (or Globe key) to switch between input methods"
