#!/bin/bash

# SupraSonic DMG Creator
# --------------------
# This script creates a disk image for SupraSonic.

set -e

APP_NAME="SupraSonic"
DMG_NAME="SupraSonic-Installer"
VERSION="1.0.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="/tmp/$DMG_NAME.dmg"
DMG_RW="/tmp/suprasonic-dmg-rw.dmg"
FINAL_DMG_PATH="$BUILD_DIR/$DMG_NAME.dmg"

# Check if app exists
if [ ! -d "$APP_PATH" ]; then
    echo "❌ App not found. Run ./build-full-app.sh first"
    exit 1
fi

echo "📀 Creating DMG with drag-to-Applications..."

# Clean previous DMG
rm -f "$DMG_PATH"
rm -f "$DMG_RW"
rm -f "$FINAL_DMG_PATH"

# Calculate size needed (app size + 200MB buffer for filesystem overhead)
APP_SIZE=$(du -sm "$APP_PATH" | cut -f1)
DMG_SIZE=$((APP_SIZE + 200))

echo "Creating read-write DMG (${DMG_SIZE}MB)..."

# Create a read-write DMG first
hdiutil create -size ${DMG_SIZE}m -fs HFS+ -volname "$APP_NAME" -o "$DMG_RW"

# Mount the DMG at /Volumes/$APP_NAME for AppleScript compatibility
MOUNT_POINT="/Volumes/$APP_NAME"

# Ensure any previous mount is gone
hdiutil detach "$MOUNT_POINT" 2>/dev/null || true

echo "Mounting DMG to $MOUNT_POINT..."
hdiutil attach -readwrite -noverify -noautoopen -mountpoint "$MOUNT_POINT" "$DMG_RW"

# Copy app
echo "Copying app to DMG..."
ditto "$APP_PATH" "$MOUNT_POINT/$APP_NAME.app"

# Create Applications folder symlink for drag-and-drop install
echo "Creating Applications symlink..."
ln -s /Applications "$MOUNT_POINT/Applications"

# Set custom volume icon
if [ -f "$APP_PATH/Contents/Resources/AppIcon.icns" ]; then
    ditto "$APP_PATH/Contents/Resources/AppIcon.icns" "$MOUNT_POINT/.VolumeIcon.icns"
    SetFile -c icnC "$MOUNT_POINT/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "$MOUNT_POINT" 2>/dev/null || true
fi

# Configure Finder window appearance with AppleScript
echo "Configuring DMG window layout..."
osascript <<EOF
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        delay 1
        set the bounds of container window to {100, 100, 640, 400}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set position of item "$APP_NAME.app" of container window to {130, 140}
        set position of item "Applications" of container window to {410, 140}
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF

# Sync and unmount
echo "Unmounting..."
sync
hdiutil detach "$MOUNT_POINT"

# Convert to compressed read-only DMG
echo "Converting to compressed DMG..."
hdiutil convert "$DMG_RW" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"

# Clean up
rm -f "$DMG_RW"
rm -rf "$DMG_TEMP"

# Move DMG to final location
mv "$DMG_PATH" "$FINAL_DMG_PATH"

echo ""
echo "✅ DMG created: $FINAL_DMG_PATH"
echo ""
echo "File size: $(du -h "$FINAL_DMG_PATH" | cut -f1)"
echo ""
echo "To test the DMG:"
echo "  open \"$FINAL_DMG_PATH\""
