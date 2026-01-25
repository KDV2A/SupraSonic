#!/bin/bash

# SupraSonic App Builder
# Creates a proper .app bundle from the Swift Package

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

echo "🔨 Building SupraSonic..."

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build the Swift package in release mode
cd "$SCRIPT_DIR/SupraSonicApp"
swift build -c release

# Get the built executable path
EXECUTABLE_PATH=$(swift build -c release --show-bin-path)/SupraSonicApp

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

# Copy Info.plist
cp "$SCRIPT_DIR/SupraSonicApp/Info.plist" "$CONTENTS_DIR/Info.plist"

# Copy resources (icons, etc.)
if [ -d "$SCRIPT_DIR/SupraSonicApp/Sources/Resources" ]; then
    cp -r "$SCRIPT_DIR/SupraSonicApp/Sources/Resources/"* "$RESOURCES_DIR/" 2>/dev/null || true
fi

# Copy the _SupraSonicApp.bundle resources if it exists (SPM resources)
BUNDLE_RESOURCES="$(swift build -c release --show-bin-path)/SupraSonicApp_SupraSonicApp.bundle"
if [ -d "$BUNDLE_RESOURCES" ]; then
    cp -r "$BUNDLE_RESOURCES" "$RESOURCES_DIR/"
fi

# Create PkgInfo
echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"

# Sign the app (ad-hoc signing for local testing)
echo "🔐 Signing app (ad-hoc)..."
codesign --force --deep --sign - "$APP_DIR"

echo ""
echo "✅ App bundle created: $APP_DIR"
echo ""
echo "To test the app:"
echo "  open \"$APP_DIR\""
echo ""
echo "To create a DMG, run:"
echo "  ./create-dmg.sh"
