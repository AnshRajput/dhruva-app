# Roadmap & Status

← [Knowledge Base](README.md)

**Current: v0.3.1** — shipped to Firebase App Distribution, verified on-device.

## Shipped

| Milestone | What landed |
|-----------|-------------|
| v0.1.0-alpha | Loops 0–7: skeleton, engine online, model hub + HF download, chat (MVP gate), characters, voice, vision |
| v0.2.x | UX hardening; **the Android 14+ download-crash fix** (foreground-service perms + `dataSync` type); dio migration; model-detail recommended-download rework |
| v0.3.0 | PRD-v0.3 rebuild of the core experience: curated mobile catalog, guided onboarding, chat upgrade, download UX, voice/playground clarity, polish pass |
| v0.3.1 | Discover-tab segmentation (**Recommended** badge + collapsed "Larger models"), onboarding fast-first-model, real speed/ETA, playground preview, honesty polish |

The v0.3 cycle is specified in [`../orchestra/PRD-v0.3.md`](../orchestra/PRD-v0.3.md);
the build history is in [`../orchestra/LOOP_LOG.md`](../orchestra/LOOP_LOG.md).

## Planned (not yet shipped)

| Loop | Name | Ships |
|------|------|-------|
| 8 | Image generation | Stable Diffusion on-device (`stable-diffusion.cpp`) |
| 9 | Documents + RAG | Ingest PDFs, chat over them with on-device embeddings |
| 10 | Toolbox | Alarms, notes, calculator via tool-calling |
| 10.5 | Playground + AI-news | Deeper A/B arena |
| 11 | Polish + arena | Cross-app consistency, model arena |
| 12–14 | Website gate, distribution CI, hardening + handover | Ship discipline |

## Known open items

- **True background-while-minimised inference** needs a native foreground service
  and isn't built yet — in-app-navigation persistence works. Tracked as R12 in
  [`../orchestra/RISKS.md`](../orchestra/RISKS.md).
- **Voice accuracy** continues to be tuned against real-device recordings.

The highest-signal next input is hands-on testing of v0.3.1 on a real phone; further
polish cycles are aimed at friction found there rather than at a fixed cycle count.
