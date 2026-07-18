# Features

← [Knowledge Base](README.md)

Each feature is a folder under `app/lib/features/` with its own `state/`, `ui/`,
and `widgets/`. Status reflects **v0.3.1**.

## Onboarding — `features/onboarding`
Guided first run: welcome → pick your first model (a small, fast model is
pre-selected and badged **Recommended**) → download with real progress → land in
chat. Shown once, skippable. This is the golden path described in
[Getting Started](getting-started.md#first-run-golden-path). **Shipped.**

## Models Hub — `features/models_hub`
The default Models experience is the **curated catalog** of phone-verified models,
not the raw Hugging Face firehose. Models that fit the device go under *"Runs great
on your phone"* with the best pick badged **Recommended**; anything too big for the
device drops into a collapsed *"Larger models"* group so the screen never promises
"runs great" for something that won't. Full HF search is demoted behind an explicit
*"Search all of Hugging Face (advanced)"* button. See [Models](models.md). **Shipped.**

## Chat — `features/chat`
Persistent conversations with streaming replies and a stop control. Suggested
starter prompts on an empty chat, a model chip showing load state, tidy
user/assistant bubbles with markdown/code, copy and regenerate actions, and
graceful "model loading" / "no model" states. Reasoning (`<think>`) blocks from
R1/DeepSeek-style models render as collapsible steps. Generation persists across
in-app navigation. **Shipped.**

## Characters — `features/characters`
Custom AI personas with their own system prompts and per-character conversation
memory. **Shipped.**

## Vision — `features/vision`
Analyze photos and screenshots on-device using a vision model + `mmproj` projector
(via `libmtmd`). Reachable through a guided path from the model catalog. **Shipped.**

## Voice — `features/voice`
Hands-free spoken exchange: speech-to-text, text-to-speech, and Silero VAD for
turn-taking, all via `sherpa_onnx`. Guided one-tap install of the voice model
bundle; listening / thinking / speaking states are shown explicitly. The VAD
`maxSpeechDuration` was raised to 20s so full utterances aren't chopped mid-sentence.
**Shipped** — accuracy continues to be tuned on real devices (see
[RISKS.md](../orchestra/RISKS.md)).

## Playground — `features/playground`
A/B compare two models side by side in two labelled columns with live tokens/sec.
Explains itself on first use and guides installing a second model, showing a preview
of the comparison before you commit to the download. **Shipped.**

## Settings — `features/settings`
App info (version kept in sync with `pubspec.yaml`), model management, and
preferences. **Shipped.**

## Planned (not yet shipped)

- **Image generation** — Stable Diffusion on-device (`stable-diffusion.cpp`)
- **Document chat (RAG)** — ingest PDFs, chat over them with on-device embeddings
- **Toolbox** — alarms, notes, calculator via tool-calling

See the [Roadmap](roadmap.md) for sequence and status.
