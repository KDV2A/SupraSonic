#!/bin/bash

# SupraSonic Launcher
# ------------------
# This script runs the SupraSonic app for testing.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🎤 Starting SupraSonic..."

# Build if needed
if [ ! -f "$SCRIPT_DIR/SupraSonicApp/.build/debug/SupraSonicApp" ]; then
    echo "🏗️  Binary not found. Building..."
    cd "$SCRIPT_DIR/SupraSonicApp"
    swift build
    cd "$SCRIPT_DIR"
fi

# Run the app
echo "🚀 Starting SupraSonic app..."
"$SCRIPT_DIR/SupraSonicApp/.build/debug/SupraSonicApp"
