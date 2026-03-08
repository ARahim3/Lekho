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

echo "=== Lekho Build ==="
echo "Build type: $BUILD_TYPE"
echo "Universal binary: $BUILD_UNIVERSAL"
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
mkdir -p "$APP_BUNDLE/Contents/Resources/data"

# Copy Info.plist
cp "$SWIFT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Copy icons
cp "$SWIFT_DIR/Resources/icon.tiff" "$APP_BUNDLE/Contents/Resources/icon.tiff"
cp "$SWIFT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Copy data files
cp "$PROJECT_ROOT/data/"*.json "$APP_BUNDLE/Contents/Resources/data/"

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Step 3: Compile Swift sources
echo ">>> Compiling Swift sources..."

SWIFT_SOURCES=(
    "$SWIFT_DIR/Sources/AppDelegate.swift"
    "$SWIFT_DIR/Sources/CandidatePanel.swift"
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
    -target arm64-apple-macos13.0
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
)

if [ "$BUILD_UNIVERSAL" = "true" ]; then
    echo ">>> Compiling for Apple Silicon..."
    swiftc "${SWIFT_SOURCES[@]}" "${SWIFT_FLAGS[@]}" \
        -L "$(dirname "$AARCH64_LIB")" \
        -target arm64-apple-macos13.0 \
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
        -target x86_64-apple-macos13.0 \
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

# Step 4: Sign the app (ad-hoc)
echo ">>> Signing app bundle..."
codesign --force --sign - \
    --entitlements "$SWIFT_DIR/Resources/Lekho.entitlements" \
    "$APP_BUNDLE"

echo ""
echo "=== Build complete ==="
echo "App bundle: $APP_BUNDLE"
echo ""
echo "To install, run: ./scripts/install.sh"
