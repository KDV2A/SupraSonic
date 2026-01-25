# SupraSonic 🎤

Fast local speech-to-text for macOS using Parakeet MLX on Apple Silicon.

## Architecture

```
[Microphone] → [Swift App (AVAudioEngine)] → [Unix Socket] → [Python ASR Server] → [Paste Text]
                    ↓
            [Dynamic Island UI]
```

## Quick Start

### 1. Start ASR Server
```bash
cd asr-backend
python3 asr_server.py
```

### 2. Run App
```bash
cd SupraSonicApp
swift run
```

### 3. Use
- **Hold Right Command (⌘)** → Record
- **Release** → Transcribe & Paste

## Requirements

- macOS 13+ (Ventura)
- Apple Silicon (M1/M2/M3)
- Python 3.11+

## Performance

- Model warmup on startup for instant inference
- ~100ms inference for 2s audio (RTF ~0.05)
- 16kHz mono audio capture
- Greedy decoding for speed

## Permissions

Grant these in System Settings > Privacy & Security:
- **Microphone**: For audio capture
- **Accessibility**: For global hotkey & paste

## Files

```
SupraSonic/
├── asr-backend/
│   ├── asr_server.py      # Python ASR server
│   └── requirements.txt
├── SupraSonicApp/
│   ├── Package.swift
│   └── Sources/
│       ├── main.swift
│       ├── AppDelegate.swift
│       └── OverlayWindow.swift
├── start.sh               # Launch both apps
└── README.md
```

## License

MIT
