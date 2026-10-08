#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE_DIR="$PROJECT_ROOT/engine"
SWIFT_DIR="$PROJECT_ROOT/Lekho"
BUILD_DIR="$PROJECT_ROOT/build"
APP_NAME="Lekho"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

# Parse arguments
BUILD_TYPE="${1:-release}"
BUILD_UNIVERSAL="${2:-false}"

# The Apple Silicon build needs macOS 13. The universal build is the extra
# download for Intel and older Macs, so it goes back to macOS 11. Its Intel half
# only links with the full Xcode toolchain: the Command Line Tools ship Swift's
# back-deployment libraries without an x86_64 slice.
MIN_MACOS="13.0"
if [ "$BUILD_UNIVERSAL" = "true" ]; then
    MIN_MACOS="11.0"
    if [ -z "${DEVELOPER_DIR:-}" ]; then
        if [ ! -d /Applications/Xcode.app ]; then
            echo "Error: the universal build needs Xcode.app (the Command Line Tools can't link it)."
            exit 1
        fi
        export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    fi
fi

echo "=== Lekho Build ==="
echo "Build type: $BUILD_TYPE"
echo "Universal binary: $BUILD_UNIVERSAL (macOS $MIN_MACOS+)"
echo ""

# Ensure cargo is available
if ! command -v cargo &>/dev/null; then
    source "$HOME/.cargo/env" 2>/dev/null || true
fi

# Step 1: Build Rust static library
echo ">>> Building Rust engine..."

CARGO_ARGS=""
if [ "$BUILD_TYPE" = "release" ]; then
    CARGO_ARGS="--release"
fi

cd "$ENGINE_DIR"

# Always build for native architecture (Apple Silicon)
cargo build $CARGO_ARGS --target aarch64-apple-darwin
AARCH64_LIB="$ENGINE_DIR/target/aarch64-apple-darwin/${BUILD_TYPE}/libavrobangla_engine.a"

if [ "$BUILD_UNIVERSAL" = "true" ]; then
    echo ">>> Building for Intel (x86_64)..."
    cargo build $CARGO_ARGS --target x86_64-apple-darwin
    X86_LIB="$ENGINE_DIR/target/x86_64-apple-darwin/${BUILD_TYPE}/libavrobangla_engine.a"

    echo ">>> Creating universal binary with lipo..."
    mkdir -p "$ENGINE_DIR/target/universal/${BUILD_TYPE}"
    FINAL_LIB="$ENGINE_DIR/target/universal/${BUILD_TYPE}/libavrobangla_engine.a"
    lipo -create "$AARCH64_LIB" "$X86_LIB" -output "$FINAL_LIB"
else
    FINAL_LIB="$AARCH64_LIB"
fi

echo ">>> Rust library built: $FINAL_LIB"

# Step 2: Create .app bundle structure
echo ">>> Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy Info.plist, stating the same minimum macOS as the binary
cp "$SWIFT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $MIN_MACOS" "$APP_BUNDLE/Contents/Info.plist"

# Copy icons (MenuIcon.tiff: full-color input-menu icon; it must be a bitmap, see generate_menu_icon.swift).
# The old iconTemplate.pdf still ships: macOS keeps an updated input method's old
# icon until the user logs out, so that path must not vanish in the meantime.
cp "$SWIFT_DIR/Resources/MenuIcon.tiff" "$APP_BUNDLE/Contents/Resources/MenuIcon.tiff"
cp "$SWIFT_DIR/Resources/iconTemplate.pdf" "$APP_BUNDLE/Contents/Resources/iconTemplate.pdf"
cp "$SWIFT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# riti compiles its dictionary/autocorrect/suffix/emoji data into the static
# library, so the data/ folder is not bundled.

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Step 3: Compile Swift sources
echo ">>> Compiling Swift sources..."

SWIFT_SOURCES=(
    "$SWIFT_DIR/Sources/AppDelegate.swift"
    "$SWIFT_DIR/Sources/Appearance.swift"
    "$SWIFT_DIR/Sources/CandidatePanel.swift"
    "$SWIFT_DIR/Sources/Engine.swift"
    "$SWIFT_DIR/Sources/InputController.swift"
    "$SWIFT_DIR/Sources/WelcomeWindow.swift"
    "$SWIFT_DIR/Sources/main.swift"
)

HEADER_SEARCH_PATH="$ENGINE_DIR/include"
BRIDGE_HEADER="$SWIFT_DIR/Sources/BridgeHeader.h"

SWIFT_FLAGS=(
    -O
    -module-name "$APP_NAME"
    -import-objc-header "$BRIDGE_HEADER"
    -I "$HEADER_SEARCH_PATH"
    -L "$(dirname "$FINAL_LIB")"
    -lavrobangla_engine
    -framework Cocoa
    -framework InputMethodKit
    -target "arm64-apple-macos$MIN_MACOS"
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
)

if [ "$BUILD_UNIVERSAL" = "true" ]; then
    echo ">>> Compiling for Apple Silicon..."
    swiftc "${SWIFT_SOURCES[@]}" "${SWIFT_FLAGS[@]}" \
        -L "$(dirname "$AARCH64_LIB")" \
        -target "arm64-apple-macos$MIN_MACOS" \
        -o "$APP_BUNDLE/Contents/MacOS/${APP_NAME}_arm64"

    echo ">>> Compiling for Intel..."
    swiftc "${SWIFT_SOURCES[@]}" \
        -O \
        -module-name "$APP_NAME" \
        -import-objc-header "$BRIDGE_HEADER" \
        -I "$HEADER_SEARCH_PATH" \
        -L "$(dirname "$X86_LIB")" \
        -lavrobangla_engine \
        -framework Cocoa \
        -framework InputMethodKit \
        -target "x86_64-apple-macos$MIN_MACOS" \
        -o "$APP_BUNDLE/Contents/MacOS/${APP_NAME}_x86_64"

    echo ">>> Creating universal Swift binary..."
    lipo -create \
        "$APP_BUNDLE/Contents/MacOS/${APP_NAME}_arm64" \
        "$APP_BUNDLE/Contents/MacOS/${APP_NAME}_x86_64" \
        -output "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

    rm "$APP_BUNDLE/Contents/MacOS/${APP_NAME}_arm64"
    rm "$APP_BUNDLE/Contents/MacOS/${APP_NAME}_x86_64"
else
    swiftc "${SWIFT_SOURCES[@]}" "${SWIFT_FLAGS[@]}"
fi

# Step 4: Sign the app. Uses the Developer ID Application certificate when one
# is in the keychain (hardened runtime + secure timestamp, both required for
# notarization), otherwise ad-hoc. Override with LEKHO_SIGN_IDENTITY; "-" forces
# ad-hoc (e.g. when offline — the timestamp needs Apple's server).
SIGN_IDENTITY="${LEKHO_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -m1 -o 'Developer ID Application: [^"]*' || true)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

CODESIGN_FLAGS=(--force --sign "$SIGN_IDENTITY" --entitlements "$SWIFT_DIR/Resources/Lekho.entitlements")
if [ "$SIGN_IDENTITY" != "-" ]; then
    CODESIGN_FLAGS+=(--options runtime --timestamp)
fi

echo ">>> Signing app bundle ($SIGN_IDENTITY)..."
codesign "${CODESIGN_FLAGS[@]}" "$APP_BUNDLE"

echo ""
echo "=== Build complete ==="
echo "App bundle: $APP_BUNDLE"
echo ""
echo "To install, run: ./scripts/install.sh"
