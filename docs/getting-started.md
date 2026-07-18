# Getting Started

← [Knowledge Base](README.md)

## What you need

- **Flutter 3.41.2** (pinned — CI uses this exact version)
- **Dart 3.11**
- Android: SDK with **minSdk 26** (Android 8.0+); a device or emulator with an
  **arm64-v8a** image and at least **4 GB RAM** (see [Models](models.md#device-tiers))
- iOS: **14.0+** (Xcode toolchain)

Inference is native, so the app runs on real hardware and arm64 emulators — not on
an x86 simulator without an arm image.

## Build from source

```bash
cd app
flutter pub get
flutter test          # unit + widget tests
make verify           # full gate: analyze + format check + tests
```

`make verify` is the same gate CI runs. It must be green before anything ships —
see [Development & Release](development.md).

## Run it

```bash
cd app
flutter run                       # attached device or running emulator
flutter build apk --release       # release APK (arm64)
```

## First-run golden path

Dhruva is designed so a first-time user reaches a working chat with zero explanation:

1. **Open** → a short welcome explains what Dhruva is and the on-device promise.
2. **Pick your first model** → the onboarding wizard pre-selects a small, fast,
   device-appropriate model marked **Recommended**.
3. **Download** → one tap, with real speed and ETA. No quant menus, no cryptic repo names.
4. **Chat** → land in a conversation with suggested starter prompts; tap one and
   watch it stream, fully offline.

Power users can reach the full Hugging Face search behind the explicit
**"Search all of Hugging Face (advanced)"** button. See [Models](models.md).

## Where things live

Work happens in [`app/`](../app) (the Flutter project root). Code is organized
feature-first under `app/lib/` — see [Architecture](architecture.md).
