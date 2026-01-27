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

# 5.5 Copy MLX Metal shaders (since swift build can't compile them)
MLX_METALLIB="/Users/kent/Library/Python/3.9/lib/python/site-packages/mlx/lib/mlx.metallib"
if [ -f "$MLX_METALLIB" ]; then
    echo "💎 Copying MLX Metal shaders..."
    cp "$MLX_METALLIB" "$RESOURCES_DIR/mlx.metallib"
else
    # Try to find it dynamically if the path above fails
    DYNAMIC_METALLIB=$(find /Users/kent/Library/Python -name "mlx.metallib" -type f | head -n 1)
    if [ -n "$DYNAMIC_METALLIB" ]; then
        echo "💎 Copying MLX Metal shaders (found dynamically)..."
        cp "$DYNAMIC_METALLIB" "$RESOURCES_DIR/mlx.metallib"
    else
        echo "⚠️ Warning: MLX Metal shaders not found. GPU may not work."
    fi
fi

# 6. Copy Rust dylib
echo "🦀 Copying Rust core library..."
cp "$SCRIPT_DIR/SupraSonicApp/Libs/libsuprasonic_core.dylib" "$MACOS_DIR/"
chmod +x "$MACOS_DIR/libsuprasonic_core.dylib"

# Create PkgInfo
echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"

# Sign the app (ad-hoc signing for local testing)
echo "🔐 Signing app (ad-hoc)..."
codesign --force --deep --sign - --entitlements "$SCRIPT_DIR/SupraSonicApp/SupraSonicApp.entitlements" "$APP_DIR"

echo ""
echo "✅ App bundle created: $APP_DIR"
echo ""
echo "To test the app:"
echo "  open \"$APP_DIR\""
echo ""
echo "To create a DMG, run:"
echo "  ./create-dmg.sh"
