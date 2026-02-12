#!/bin/bash

# SupraSonic App Builder
# --------------------
# This script builds the SupraSonic app bundle.

set -e

APP_NAME="SupraSonic"
BUNDLE_ID="com.suprasonic.app"
VERSION="1.0.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Change to the app's directory
cd "$SCRIPT_DIR/SupraSonicApp"

# 1. Build the binary
echo "🏗️ Building Swift binary..."
swift build -c release

# Get the built executable path
EXECUTABLE_PATH=$(swift build -c release --show-bin-path)/SupraSonicApp

if [ ! -f "$EXECUTABLE_PATH" ]; then
    echo "❌ Build failed: executable not found"
    exit 1
fi

# 2. Create the app bundle structure
echo "📦 Creating app bundle structure..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# 3. Copy files
echo "📄 Copying executable and resources..."
cp "$EXECUTABLE_PATH" "$MACOS_DIR/SupraSonicApp"

# 4. Copy Plist
cp "$SCRIPT_DIR/SupraSonicApp/Info.plist" "$CONTENTS_DIR/Info.plist"

# 5. Copy Resources
if [ -d "$SCRIPT_DIR/SupraSonicApp/Sources/Resources" ]; then
    cp -r "$SCRIPT_DIR/SupraSonicApp/Sources/Resources/"* "$RESOURCES_DIR/" 2>/dev/null || true
fi

# Copy the _SupraSonicApp.bundle resources if it exists (SPM resources)
BUNDLE_RESOURCES="$(swift build -c release --show-bin-path)/SupraSonicApp_SupraSonicApp.bundle"
if [ -d "$BUNDLE_RESOURCES" ]; then
    cp -r "$BUNDLE_RESOURCES" "$RESOURCES_DIR/"
fi

# 6. Copy Rust dylib
echo "🦀 Copying Rust core library..."
cp "$SCRIPT_DIR/SupraSonicApp/Libs/libsuprasonic_core.dylib" "$MACOS_DIR/"
chmod +x "$MACOS_DIR/libsuprasonic_core.dylib"

# 7. Strip binaries to reduce size
echo "✂️ Stripping binaries..."
strip -x "$MACOS_DIR/SupraSonicApp"
strip -x "$MACOS_DIR/libsuprasonic_core.dylib"

# 7.5 Fix dylib reference (Change from absolute to @executable_path)
echo "🔗 Fixing library reference path..."
# Use install_name_tool to change the ID of the dylib and the reference in the binary
install_name_tool -id "@executable_path/libsuprasonic_core.dylib" "$MACOS_DIR/libsuprasonic_core.dylib"
install_name_tool -change "/Users/kent/Desktop/SupraSonic/target/release/deps/libsuprasonic_core.dylib" "@executable_path/libsuprasonic_core.dylib" "$MACOS_DIR/SupraSonicApp"

# 8. Sign the components individually first
echo "🔐 Signing components..."
codesign --force --sign - "$MACOS_DIR/libsuprasonic_core.dylib"

# 9. Sign the app (ad-hoc signing for local testing)
echo "🔐 Signing app (ad-hoc)..."
codesign --force --sign - --entitlements "$SCRIPT_DIR/SupraSonicApp/SupraSonicApp.entitlements" "$APP_DIR"

# 10. Remove quarantine attribute (fixes translocation issues for local testing)
echo "🛡️ Removing quarantine attribute..."
xattr -rc "$APP_DIR" || true

echo ""
echo "✅ App bundle created: $APP_DIR"
echo ""
echo "To test the app:"
echo "  open \"$APP_DIR\""
echo ""
echo "To create a DMG, run:"
echo "  ./create-dmg.sh"
