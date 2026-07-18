# Dhruva AI — Knowledge Base

**Your AI. Your phone. Nobody else's business.**

Dhruva is an open-source Flutter app (Android + iOS) that runs LLMs **100% on-device**:
chat, characters, vision, voice, and an A/B model playground — with zero telemetry
and no cloud path. The only network call the app ever makes is a user-initiated
model download from Hugging Face.

This folder is the project's documentation web. Start here, then follow the links.

## Map

| Doc | What it covers |
|-----|----------------|
| [Getting Started](getting-started.md) | Install, build from source, run on a device/emulator, first chat |
| [Privacy & the On-Device Contract](privacy.md) | The non-negotiable: 100% local inference, zero telemetry — and how it's enforced |
| [Architecture](architecture.md) | Feature-first layers, engine bindings, state, data, isolates |
| [Features](features.md) | Every user-facing feature and its current status |
| [Models & the Curated Catalog](models.md) | Curated mobile catalog, device tiers, RAM floors, adding a model |
| [Development & Release](development.md) | `make verify`, testing, the loop process, Firebase distribution |
| [Roadmap & Status](roadmap.md) | What's shipped (v0.3.1) vs. planned |

## Deeper references

- **Architecture Decision Records** — [`adr/`](adr/): [inference engine](adr/001-inference-engine.md),
  [app architecture](adr/002-app-architecture.md), [brand identity](adr/003-brand-identity.md)
- **Design specs** — [`design/chat-spec.md`](design/chat-spec.md)
- **Product requirements** — [`../orchestra/PRD-v0.3.md`](../orchestra/PRD-v0.3.md)
- **Build history** — [`../orchestra/LOOP_LOG.md`](../orchestra/LOOP_LOG.md),
  [`../orchestra/RISKS.md`](../orchestra/RISKS.md)

## The one-paragraph pitch

There's a trust gap at the heart of modern AI: every online chat sends your words to
someone else's server. Dhruva closes it. The name comes from ध्रुव — the pole star,
the one fixed point that never moves. Your models live on your phone; they answer
offline; nothing reports back.

---
Current version: **v0.3.1** · License: **Apache-2.0** · Built by **Appu Inside Engineering**.
