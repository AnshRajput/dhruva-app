# TASKS — living kanban

## ROADMAP (locked 2026-07-17, Loop 0 gate)
L1 skeleton+org → L2 engine online → L3 model manager+HF hub → L4 chat →
L5 characters → L6 voice → L7 vision → L8 imagine → L9 docs RAG → L10 toolbox →
L10.5 playground+AI-news (SCOPE AMENDMENT 1) → L11 polish+arena → L12 website →
L13 distribution → L14 hardening+handover → CONTINUOUS MODE.
Designer review BLOCKING at every gate from L4 on (AMENDMENT 1b).

**MVP (Loops 1–4):** install → browse HF → download a recommended model →
genuinely pleasant offline chat. Tag v0.1.0-alpha at MVP gate.

**Scope amendments from Loop 0 research:**
- Loop 4 chat MUST include reasoning-token transparency (collapsible
  `<think>` block rendering) — top user ask, cheap to ship.
- Loop 6 voice is judged on ORCHESTRATION (VAD, turn-taking, interruption),
  not raw STT/TTS presence.
- Device floor: minSdk 26 (Android 8.0), iOS 14+. Tiers: 1B models → 4GB+
  RAM, 3B+ → 6GB+.
- Starter catalog (verified repos): Llama-3.2-1B/3B, Qwen2.5-1.5B,
  SmolLM2-1.7B, Phi-4-mini (bartowski/unsloth GGUF Q4_K_M); embeddings
  All-MiniLM-L6-v2; vision SmolVLM2-2.2B + mmproj.

## IN-LOOP (Loop 0 — closing)
- [x] Competitor feature matrix — scout-1
- [x] Engine bindings research — scout-2 (version claims corrected by orchestrator)
- [x] HF API verification + NAMING dossier — scout-3
- [x] ADR-001 engine choice (llama_cpp_dart @ pinned git commit) — ACCEPTED
- [x] ADR-002 app architecture (feature-first) — ACCEPTED
- [x] Name ratified: DHRUVA (display "Dhruva AI")
- [ ] design-tokens.json + ADR-003 — designer (IN PROGRESS) → reviewer critique → ratify
- [x] Roadmap + MVP scope locked (this file)

## BACKLOG (triaged)
- Reviewer N2 (Loop 4): committed 2.4MB AAR → consider Git-LFS or CI-fetch
- Reviewer N3 (Loop 4): streaming hot-path headroom at 4096 max tokens —
  RepaintBoundary on bubbles, O(n²) _rawBuffer accumulation; profile in the
  Loop 11 performance pass
- App credit row (AMENDMENT 2b): "Made with ❤️ by Ansh Singh Rajput" →
  anshgandharva.online on the settings/about surface — land in Loop 5
- Vercel production deploy of website at Loop 12 gate (AMENDMENT 2a)
- Downloads: same-basename subfolder collision (a/model.gguf vs b/model.gguf
  flatten to one local name) — encode subfolder into on-disk name when a real
  repo needs it (reviewer carry-forward, Loop 3)
- Engine follow-up (reviewer nit, Loop 2): widen worker bootstrap try to cover
  ChatTemplate.fromModel/LlamaSession; add timeout on ready.future (leak+hang
  path, low probability) — fold into Loop 3 or 4 engine touch
- Cross-device model/chat sync over LAN/P2P, opt-in, no cloud (scout-1 idea #1;
  pairs with LAN server mode stretch)
- Agentic on-device tool use (alarms/notes intents) — existing stretch
- NPU acceleration (llama_cpp_dart Hexagon AAR exists — revisit post-V1)
- Home-screen widgets / iOS Shortcuts, character marketplace page, F-Droid,
  Play Store kit, full Hindi UI pass

## BLOCKED
(none)

## DONE
- [x] Factory verification — orchestrator
- [x] Workspace + orchestra + agent roster seeded — orchestrator
- [x] Local git repos initialized (dhruva-app, dhruva-website), Apache-2.0
