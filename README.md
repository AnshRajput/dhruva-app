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

## Status: Pre-Alpha

Dhruva is scaffolding now. We're building in public with a locked roadmap. Think of this as a foundation; features are landing loop by loop.

| Phase | Name | Status | What Ships |
|-------|------|--------|-----------|
| 1 | **Skeleton + org** | 🔄 In progress | Project structure, CI, build system, icon |
| 2 | **Engine online** | ⏳ Planned | llama_cpp_dart bindings working, first chat |
| 3 | **Model manager + HF hub** | ⏳ Planned | Download any GGUF from Hugging Face, model browser |
| 4 | **Chat** | ⏳ Planned | Persistent conversations, reasoning-token transparency, **MVP gate → v0.1.0-alpha** |
| 5 | **Characters** | ⏳ Planned | Custom personas, system prompts, roleplay |
| 6 | **Voice** | ⏳ Planned | STT + TTS with proper orchestration, VAD, turn-taking |
| 7 | **Vision** | ⏳ Planned | Photo & screenshot analysis with SmolVLM2 + mmproj |
| 8 | **Image generation** | ⏳ Planned | Stable Diffusion on-device |
| 9 | **Documents + RAG** | ⏳ Planned | Ingest PDFs, chat over them with local embeddings |
| 10 | **Toolbox** | ⏳ Planned | Alarms, notes, calculator, tool-calling orchestration |

**MVP (Loops 1–4):** install → browse Hugging Face → download a model → genuinely pleasant offline chat. Tagged v0.1.0-alpha.

## Features (Coming)

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
