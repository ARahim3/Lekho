.PHONY: build build-universal install uninstall clean

# Default: build for Apple Silicon only (release)
build:
	@bash scripts/build.sh release false

# Build universal binary (Apple Silicon + Intel)
build-universal:
	@bash scripts/build.sh release true

# Debug build (Apple Silicon only)
build-debug:
	@bash scripts/build.sh debug false

# Install to ~/Library/Input Methods/
install: build
	@bash scripts/install.sh

# Install universal binary
install-universal: build-universal
	@bash scripts/install.sh

# Uninstall
uninstall:
	@bash scripts/uninstall.sh

# Clean build artifacts
clean:
	rm -rf build/
	cd engine && cargo clean

# Run Rust tests
test:
	cd engine && cargo test
