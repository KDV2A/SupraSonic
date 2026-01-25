#!/bin/bash

# Suprasonic Full App Builder
# Creates a self-contained .app bundle with WhisperKit (no Python needed)

set -e

APP_NAME="Suprasonic"
BUNDLE_ID="com.suprasonic.app"
VERSION="1.0.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "🔨 Building Suprasonic (WhisperKit Native)..."
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
cp -r "$SCRIPT_DIR/SuprasonicApp" "$SWIFT_BUILD_DIR/"
cd "$SWIFT_BUILD_DIR/SuprasonicApp"
rm -rf .build

# Resolve and fetch dependencies first
echo "📥 Fetching dependencies (WhisperKit)..."
swift package resolve

# Build release
swift build -c release
cd "$SCRIPT_DIR"

EXECUTABLE_PATH="$SWIFT_BUILD_DIR/SuprasonicApp/.build/release/SuprasonicApp"

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
cp "$EXECUTABLE_PATH" "$MACOS_DIR/SuprasonicApp"

# Copy Info.plist
cp "$SCRIPT_DIR/SuprasonicApp/Info.plist" "$CONTENTS_DIR/Info.plist"

# Copy app resources
if [ -d "$SCRIPT_DIR/SuprasonicApp/Sources/Resources" ]; then
    ditto "$SCRIPT_DIR/SuprasonicApp/Sources/Resources/" "$RESOURCES_DIR/"
fi

# Copy app icon
if [ -f "$SCRIPT_DIR/SuprasonicApp/Sources/Resources/AppIcon.icns" ]; then
    ditto "$SCRIPT_DIR/SuprasonicApp/Sources/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
    echo "✅ App icon copied"
fi

# Copy SPM bundle resources from the /tmp build
BUNDLE_RESOURCES="$SWIFT_BUILD_DIR/SuprasonicApp/.build/release/SuprasonicApp_SuprasonicApp.bundle"
if [ -d "$BUNDLE_RESOURCES" ]; then
    ditto "$BUNDLE_RESOURCES" "$RESOURCES_DIR/SuprasonicApp_SuprasonicApp.bundle"
fi

# Create PkgInfo
echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"

echo "ℹ️ WhisperKit models will be downloaded by the app on first launch"

# Ad-hoc sign the app bundle with entitlements
echo "🔐 Signing app bundle components..."

# 1. Sign the sub-bundle if it exists
BUNDLE_PATH="$RESOURCES_DIR/SuprasonicApp_SuprasonicApp.bundle"
if [ -d "$BUNDLE_PATH" ]; then
    echo "   Signing sub-bundle..."
    codesign --force --sign - "$BUNDLE_PATH" || true
fi

# 2. Sign the main executable
echo "   Signing main executable..."
codesign --force --sign - --entitlements "$SCRIPT_DIR/SuprasonicApp/SuprasonicApp.entitlements" "$MACOS_DIR/SuprasonicApp"

# 3. Sign the app bundle
echo "   Signing app bundle..."
codesign --force --sign - --entitlements "$SCRIPT_DIR/SuprasonicApp/SuprasonicApp.entitlements" "$APP_DIR"

echo "✅ App signed with ad-hoc signature"

# Calculate final size
APP_SIZE=$(du -sh "$APP_DIR" | cut -f1)

echo ""
echo "✅ Suprasonic built successfully!"
echo ""
echo "   Location: $APP_DIR"
echo "   Size: $APP_SIZE (no Python, no bundled models)"
echo ""
echo "To test the app:"
echo "   open \"$APP_DIR\""
echo ""
echo "To create a DMG for distribution:"
echo "   ./create-dmg.sh"
