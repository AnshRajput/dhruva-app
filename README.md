# Dhruva AI

**Your AI. Your phone. Nobody else's business.**

[![CI](https://github.com/AnshRajput/dhruva-app/actions/workflows/ci.yml/badge.svg)](https://github.com/AnshRajput/dhruva-app/actions)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

## Why Dhruva?

There's a trust gap at the heart of modern AI: every time you chat with an LLM online, your words leave your device—to a company, a server, a database somewhere. Dhruva closes that gap. **100% inference happens on-device. The only network calls are your own:** downloading a model from Hugging Face, nothing more. No telemetry, no tracking, no endpoints that report back.

The name comes from ध्रुव (Dhruva), the pole star in Hindu astronomy—the one fixed point in the night sky that never moves. Dhruva AI is the same: always there, needs no network, yours alone to navigate by.

## What it does

**Offline chat** with any quantized GGUF model from Hugging Face (Llama, Qwen, Phi, SmolLM, and more). **Characters** with custom personalities and system prompts. **Vision** for analyzing photos and screenshots. **Image generation** from text. **Voice** with speech-to-text and text-to-speech (both directions). **Document chat** via on-device RAG. **One-tap toolbox** for common tasks—all running 100% locally, with zero external dependencies.

## Status: v0.3.1

Chat, characters, voice, vision, a curated mobile model catalog, guided onboarding,
and an A/B model playground are **shipped and running on-device**. Building in public,
loop by loop. Full detail in the [documentation knowledge base](docs/README.md).

| Feature | Status |
|---------|--------|
| Guided onboarding (pick → download → chat) | ✅ Shipped |
| Curated mobile model catalog + HF advanced search | ✅ Shipped |
| Offline streaming chat + reasoning transparency | ✅ Shipped |
| Characters (custom personas) | ✅ Shipped |
| Voice (STT + TTS + VAD) | ✅ Shipped |
| Vision (photo/screenshot analysis) | ✅ Shipped |
| Playground (A/B model compare) | ✅ Shipped |
| Image generation | ⏳ Planned (Loop 8) |
| Documents + RAG | ⏳ Planned (Loop 9) |
| Toolbox | ⏳ Planned (Loop 10) |

See the [Roadmap](docs/roadmap.md) for what's next.

## Documentation

The full knowledge base lives in [`docs/`](docs/README.md):
[Getting Started](docs/getting-started.md) ·
[Privacy](docs/privacy.md) ·
[Architecture](docs/architecture.md) ·
[Features](docs/features.md) ·
[Models](docs/models.md) ·
[Development & Release](docs/development.md) ·
[Roadmap](docs/roadmap.md)

## Features

- **Any GGUF model** — Download from Hugging Face without going through a walled garden. If it's quantized, it works.
- **Reasoning transparency** — See `<think>` blocks from R1/DeepSeek models as collapsible reasoning steps, not tangled output.
- **Cross-platform Polish** — Android 8+ and iOS 14+ with a real design system, not bolted-on afterthought.
- **Character library** — Roleplay with custom AI personas, system prompts, conversation memory per character.
- **Voice both ways** — Whisper-based STT + sherpa-onnx TTS. Listen to the AI, talk back.
- **Vision** — Analyze photos and screenshots with SmolVLM2, without leaving the device.
- **Image generation** — Stable Diffusion quantized, running on-phone.
- **Document chat** — Upload PDFs; ask questions against them using on-device embeddings and retrieval.
- **True offline** — Works completely without network. Download a model once; chat forever offline.
- **Zero telemetry** — No analytics SDKs, no feature flags that phone home, no A/B testing endpoints. Open-source, auditable.

## Runs on

**Android:** 8.0+ (minSdk 26)  
**iOS:** 14.0+

**RAM requirements:**
- **1B models** → 4GB+ RAM
- **3–4B models** → 6GB+ RAM
- **7B+ models** → 8GB+

Starter models (verified, quantized Q4_K_M): Llama-3.2-1B, Qwen2.5-1.5B, SmolLM2-1.7B, Phi-4-mini. Vision: SmolVLM2-2.2B with mmproj. Embeddings: All-MiniLM-L6-v2.

## Building from source

```bash
cd app
flutter pub get
flutter test
make verify  # full gate: analyze + format + tests
```

See `CONTRIBUTING.md` for the full setup and branch workflow.

## Contributing

We welcome code, documentation, translations, bug reports, and model catalog entries. See [CONTRIBUTING.md](CONTRIBUTING.md) for ground rules and setup.

**Ground rules:**
- Privacy is non-negotiable. No telemetry, no cloud fallback, ever.
- Tested code only. `make verify` must pass.
- Small, conventional commits.

## License

Dhruva is **Apache License 2.0**. See [LICENSE](LICENSE).

---

Built by **Appu Inside Engineering**.

*Not affiliated with AI4Bharat's Dhruva speech platform.*
