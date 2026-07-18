# PRD v0.3 — "Make Dhruva genuinely easy to use"

Author: orchestrator acting as senior PM. Date: 2026-07-18.
Trigger: human is unsatisfied — "the experience is not good… this should be easy
to use… I don't know what is missing." Concrete complaints: downloading,
chatting, voice, playground, and the models list showing "n number of models"
instead of only mobile-capable ones.

## The core diagnosis
Dhruva has grown many features (chat, characters, voice, vision, playground) but
the CORE EXPERIENCE isn't tight. The three root problems:
1. **Discovery is a firehose.** The Models → Search tab dumps raw Hugging Face
   results — dozens of cryptic repos (`bartowski/…`, `handy-computer/nemotron-…`),
   many NOT actually runnable on a phone. A normal user cannot tell what to pick.
2. **No guidance.** First run drops the user at an empty state with a "Browse
   models" button into that firehose. No "pick your first model → download →
   chat" wizard. Every feature assumes the user already knows what to do.
3. **Primary action per screen is unclear.** Too many affordances, not enough
   "here's the one thing to do next." Interface consistency and polish vary.

## Product principles (the bar every change is held to)
- **One obvious next step on every screen.** A first-time user, given the phone,
  completes the golden path (open → get a model → chat) with zero explanation.
- **Curated over comprehensive.** Show a small, hand-verified set of models that
  genuinely run well on phones. Power users get "search all of Hugging Face"
  behind an explicit Advanced affordance.
- **Honest, calm UI.** Consistent spacing/typography/states from design-tokens,
  premium dark theme, no dead ends, every long op cancellable with real progress.
- **Real value stated, not implied.** Each surface says what it's for.
- **100% on-device, zero telemetry** — unchanged, non-negotiable.

## Golden path (must be effortless)
Open app → (first run) friendly welcome → "Pick your first model" with a
device-appropriate default pre-selected → one-tap download with clear progress →
"Ready" → land in chat with 3 suggested prompts → tap one → smooth streaming
reply. No jargon, no quant menus, no cryptic repo names in the default flow.

## Workstreams (prioritized). Each has ACCEPTANCE CRITERIA.

### WS1 — Curated mobile-model catalog (P0, biggest win)
Replace the raw-HF-firehose as the DEFAULT with a curated catalog of ~10–12
models verified to run on phones, each with: friendly name, one-line "best for…",
size, device verdict (Comfortable/Possible), and ONE download button (auto-picks
the right quant). Raw HF search demoted to an "Search all of Hugging Face
(advanced)" entry that STRICTLY filters to mobile-runnable GGUF (params ≤ ~4B AND
a Q4-class quant AND total size within the device tier). Curated set (starting
point, refine): Llama 3.2 1B & 3B Instruct, Qwen2.5 0.5B/1.5B/3B Instruct, Gemma
2 2B, Phi-3.5-mini, SmolLM2 1.7B, TinyLlama 1.1B, plus one strong vision model
(SmolVLM/Qwen2-VL 2B) and the voice bundle. Each entry curated with a known-good
repo+quant so downloads "just work."
- ACCEPTANCE: default Models screen shows the curated list only; no cryptic
  raw-HF rows by default; each card downloads a working model in one tap;
  advanced search is reachable but clearly secondary and filters out non-mobile
  models; verdicts are correct for the device.

### WS2 — Guided first-run onboarding (P0)
A first-launch flow: welcome (what Dhruva is, 1 sentence + the value) → "Pick your
first model" (curated, device default highlighted, "Recommended" badge) →
download with progress → success → into chat with suggested prompts. Skippable,
shown once.
- ACCEPTANCE: a fresh install reaches a working first chat without the user ever
  seeing the raw model firehose or a quant menu; onboarding shows once.

### WS3 — Chat experience upgrade (P0)
Make chat feel advanced + friendly: suggested starter prompts on empty chat, a
clear model chip with load state, smooth streaming with stop, tidy user/assistant
bubbles + code/markdown, quick actions (copy, regenerate) that are discoverable,
graceful "model still loading" and "no model" states, and a clean composer.
Address any perceived jank.
- ACCEPTANCE: empty chat offers tappable suggested prompts; sending → visible
  "thinking"/streaming → stoppable; switching model is obvious; no confusing
  dead states; scrolls smoothly.

### WS4 — Download experience (P0)
Make downloading obviously-working and reassuring: clear per-model status, real
speed+ETA, "Ready — start chatting" completion with a direct CTA, visible
queue/cancel, resilient resume, and no way to end up confused about whether a
model is installed. Reconcile Models tab / Installed / chat model list so a
freshly downloaded model appears everywhere immediately.
- ACCEPTANCE: from tapping Download to chatting is a clear, guided path;
  in-progress and done states are unambiguous; a downloaded model appears in
  Installed and in the chat model picker with no restart.

### WS5 — Voice agent (P1)
Clarify the whole voice flow: obvious entry point, clear setup ("download the
voice models" if missing, one tap), unambiguous listening/thinking/speaking
states, and the accuracy fix verified. Make hands-free feel intentional.
- ACCEPTANCE: a user can find voice, install its models in one guided step, and
  have a spoken exchange with clear state feedback; STT captures full sentences.

### WS6 — Playground clarity (P1)
Make the value obvious and the flow smooth: explain what it's for in one line,
guide installing a 2nd model, make the A/B compare visually clear (two labelled
columns, live tok/s, winner-ish framing), and make AI-news feel purposeful.
- ACCEPTANCE: first-time Playground explains itself; comparing two models is one
  guided flow; both columns stream; no empty/confusing states.

### WS7 — Interface consistency & polish pass (P1)
A cross-app pass for spacing rhythm, typography hierarchy, consistent cards/
states/empty-states/motion, tap targets, and dark-theme correctness. Kill any
remaining "AI-generated flat" feel; make it feel crafted.
- ACCEPTANCE: screens feel consistent and premium; no jarring spacing/typography;
  all states (empty/loading/error) designed; motion is calm ease-out.

## Out of scope (this cycle)
Background-while-minimised inference (needs a native foreground service — tracked
separately), image generation (Loop 8), docs RAG, toolbox. New model
architectures beyond what llama.cpp supports.

## Definition of done for the cycle
make verify green; each workstream's acceptance criteria met and verified on the
emulator by the orchestrator (screenshots); golden path works end-to-end on a
fresh install; shipped to Firebase.
