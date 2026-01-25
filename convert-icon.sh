#!/bin/bash

# Convert PNG to ICNS
# Usage: ./convert-icon.sh input.png output.icns

INPUT_PNG="$1"
OUTPUT_ICNS="$2"
ICONSET_DIR="temp.iconset"

if [ -z "$INPUT_PNG" ] || [ -z "$OUTPUT_ICNS" ]; then
    echo "Usage: $0 input.png output.icns"
    exit 1
fi

mkdir -p "$ICONSET_DIR"

# Standard sizes for macOS app icons
sips -s format png -z 16 16     "$INPUT_PNG" --out "$ICONSET_DIR/icon_16x16.png"
sips -s format png -z 32 32     "$INPUT_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png"
sips -s format png -z 32 32     "$INPUT_PNG" --out "$ICONSET_DIR/icon_32x32.png"
sips -s format png -z 64 64     "$INPUT_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png"
sips -s format png -z 128 128   "$INPUT_PNG" --out "$ICONSET_DIR/icon_128x128.png"
sips -s format png -z 256 256   "$INPUT_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png"
sips -s format png -z 256 256   "$INPUT_PNG" --out "$ICONSET_DIR/icon_256x256.png"
sips -s format png -z 512 512   "$INPUT_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png"
sips -s format png -z 512 512   "$INPUT_PNG" --out "$ICONSET_DIR/icon_512x512.png"
sips -s format png -z 1024 1024 "$INPUT_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png"

iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"
rm -rf "$ICONSET_DIR"

echo "✅ Created $OUTPUT_ICNS"
