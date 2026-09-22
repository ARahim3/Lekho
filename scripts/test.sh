#!/bin/bash
# Headless integration test: drives the real LekhoInputController (+ shared riti
# engine) with synthesized key events against a mock text client. Uses a scratch
# user dir (LEKHO_USER_DIR), so real learned selections are never touched.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE_DIR="$PROJECT_ROOT/engine"
SRC="$PROJECT_ROOT/Lekho/Sources"
OUT="$PROJECT_ROOT/build/test"

source "$HOME/.cargo/env" 2>/dev/null || true

echo ">>> Building Rust engine..."
(cd "$ENGINE_DIR" && cargo build --release --target aarch64-apple-darwin)

echo ">>> Compiling integration test..."
mkdir -p "$OUT"
swiftc -O -module-name LekhoTest \
    "$SRC/InputController.swift" "$SRC/Engine.swift" "$SRC/CandidatePanel.swift" "$SRC/Appearance.swift" \
    "$PROJECT_ROOT/tests/integration/main.swift" \
    -import-objc-header "$SRC/BridgeHeader.h" \
    -I "$ENGINE_DIR/include" \
    -L "$ENGINE_DIR/target/aarch64-apple-darwin/release" -lavrobangla_engine \
    -framework Cocoa -framework InputMethodKit \
    -target arm64-apple-macos13.0 \
    -o "$OUT/lekho_test"

echo ">>> Running..."
LEKHO_USER_DIR="$OUT/userdir" "$OUT/lekho_test"
