#!/bin/bash
# SupraSonic Launcher
# Starts both the ASR backend and the Swift app

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "🎤 Starting SupraSonic..."

# Start ASR server in background
echo "📦 Starting ASR server..."
/opt/homebrew/opt/python@3.11/bin/python3.11 "$SCRIPT_DIR/asr-backend/asr_server_whisper.py" &
ASR_PID=$!

# Wait for server to be ready
sleep 3

# Check if server started
if ! kill -0 $ASR_PID 2>/dev/null; then
    echo "❌ ASR server failed to start"
    exit 1
fi

echo "✅ ASR server running (PID: $ASR_PID)"

# Start Swift app
echo "🚀 Starting SupraSonic app..."
"$SCRIPT_DIR/SupraSonicApp/.build/debug/SupraSonicApp"

# Cleanup on exit
echo "👋 Shutting down..."
kill $ASR_PID 2>/dev/null
