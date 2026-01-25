#!/bin/bash

# SupraSonic Full App Builder
# -------------------------
# This script builds the SupraSonic app bundle including all resources.

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

echo "🔨 Building SupraSonic (WhisperKit Native)..."
echo "   This will create a self-contained Swift app."
echo ""

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build Swift app from /tmp to avoid Desktop path in binary
echo "📦 Building Swift app with WhisperKit..."
SWIFT_BUILD_DIR="/tmp/suprasonic-swift-build"
rm -rf "$SWIFT_BUILD_DIR"
mkdir -p "$SWIFT_BUILD_DIR"
cp -r "$SCRIPT_DIR/SupraSonicApp" "$SWIFT_BUILD_DIR/"
cd "$SWIFT_BUILD_DIR/SupraSonicApp"

# 1. Build the binary
echo "🏗️ Building Swift binary..."
swift build -c release

# Get the built executable path
EXECUTABLE_PATH="$SWIFT_BUILD_DIR/SupraSonicApp/.build/release/SupraSonicApp"

if [ ! -f "$EXECUTABLE_PATH" ]; then
    echo "❌ Build failed: executable not found"
    exit 1
fi

echo "✅ Swift build complete"

# Create app bundle structure
echo "📦 Creating app bundle..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
cp "$EXECUTABLE_PATH" "$MACOS_DIR/SupraSonicApp"

# 4. Copy Plist
cp "$SCRIPT_DIR/SupraSonicApp/Info.plist" "$CONTENTS_DIR/Info.plist"

# 5. Copy Resources
if [ -d "$SCRIPT_DIR/SupraSonicApp/Sources/Resources" ]; then
    ditto "$SCRIPT_DIR/SupraSonicApp/Sources/Resources/" "$RESOURCES_DIR/"
fi

# 6. Copy App Icon
if [ -f "$SCRIPT_DIR/SupraSonicApp/Sources/Resources/AppIcon.icns" ]; then
    ditto "$SCRIPT_DIR/SupraSonicApp/Sources/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# 7. Copy Bundle Resources
# Handle the SPM resource bundle
BUNDLE_RESOURCES="$SWIFT_BUILD_DIR/SupraSonicApp/.build/release/SupraSonicApp_SupraSonicApp.bundle"
if [ -d "$BUNDLE_RESOURCES" ]; then
    ditto "$BUNDLE_RESOURCES" "$RESOURCES_DIR/SupraSonicApp_SupraSonicApp.bundle"
fi

# 8. Set up framework structure if needed (Optional for now)

# Create PkgInfo
echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"

# 9. Signing
echo "🔐 Signing app..."

# Sign the helper bundle if it exists
BUNDLE_PATH="$RESOURCES_DIR/SupraSonicApp_SupraSonicApp.bundle"
if [ -d "$BUNDLE_PATH" ]; then
    codesign --force --sign - "$BUNDLE_PATH"
fi

# Sign main binary with entitlements
codesign --force --sign - --entitlements "$SCRIPT_DIR/SupraSonicApp/SupraSonicApp.entitlements" "$MACOS_DIR/SupraSonicApp"

# Sign entire bundle
codesign --force --sign - --entitlements "$SCRIPT_DIR/SupraSonicApp/SupraSonicApp.entitlements" "$APP_DIR"

echo ""
echo "✅ SupraSonic built successfully!"

# Calculate final size
APP_SIZE=$(du -sh "$APP_DIR" | cut -f1)

echo ""
echo ""
echo "   Location: $APP_DIR"
echo "   Size: $APP_SIZE (no Python, no bundled models)"
echo ""
echo "To test the app:"
echo "   open \"$APP_DIR\""
echo ""
echo "To create a DMG for distribution:"
echo "   ./create-dmg.sh"
