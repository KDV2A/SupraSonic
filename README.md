# SupraSonic 🎤

Fast local speech-to-text for macOS using Parakeet MLX on Apple Silicon.

## Architecture

```
[Microphone] → [SupraSonicApp (AVAudioEngine)] → [FluidAudio (Parakeet MLX)] → [Paste Text]
                        ↓
                [Dynamic Island HUD]
```

## Quick Start

### 1. Build & Run
```bash
./build-app.sh
open build/SupraSonic.app
```

### 2. Initial Setup
Follow the onboarding to grant Microphone and Accessibility permissions. The app will automatically download the required ML model (~600MB).

### 3. Use
- **Hold Right Command (⌘)** → Record
- **Release** → Transcribe & Paste

(You can customize the "Magic Key" and behavior in the Settings menu)

## Requirements

- macOS 14.0+ (Sonoma)
- Apple Silicon (M1/M2/M3/M4)
- No Python required (Native Swift)

## Performance

- Model warmup on startup for instant inference.
- Powered by NVIDIA Parakeet TDT via MLX/FluidAudio.
- 16kHz mono audio capture.

## Permissions

Grant these in System Settings > Privacy & Security:
- **Microphone**: For audio capture.
- **Accessibility**: For global hotkey & paste functionality.

## Project Structure

```
SupraSonic/
├── SupraSonicApp/        # Swift Package source code
│   ├── Package.swift
│   └── Sources/          # App logic and UI
├── build-app.sh          # Quick build script
├── build-full-app.sh     # Production build script
├── create-dmg.sh         # DMG installer creator
└── README.md
```

## License

MIT
