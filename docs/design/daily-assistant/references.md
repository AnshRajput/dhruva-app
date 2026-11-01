# Dhruva AI redesign: reference landscape

Note: written from training knowledge (cutoff ~mid-2026); URLs are canonical product pages/repos, NOT live-verified this run. Re-check before quoting features externally.

## 1. On-device AI apps: IA and daily hooks

| App | Home / IA | Daily hook | Gap |
|---|---|---|---|
| PocketPal AI (github.com/a-ghorbani/pocketpal-ai) | Chat, Models (HF browser/download), Benchmark, Settings; "Pals" (personas) | Pals, benchmark leaderboard | Pure chat; no personal data |
| Google AI Edge Gallery (github.com/google-ai-edge/gallery) | Task tiles: Ask Image, Audio Scribe, Prompt Lab, AI Chat | Task-first tiles, not chat-first | Demo/showcase; no memory |
| Private LLM (privatellm.app) | Chat + model list, Siri Shortcuts, system-wide text actions | Shortcuts/share-sheet integration | Paid; no connectors |
| Enclave (enclaveai.app) | Chat, local RAG on docs, privacy-framed | "Private" positioning | Narrow |
| Apollo AI (apolloliquid.com) | Chat, model picker, optional remote models | Fast model switching | Chat only |
| Locally AI (locallyai.app) | Minimal chat, Apple MLX, Shortcuts | Polished native feel, Shortcuts | No data sources |
| LM Studio mobile / LM Link | Remote-to-desktop chat | Reach home-GPU models | Not on-device |
| MLC Chat (llm.mlc.ai) | Model list then chat | None | Engineering demo |
| Layla (layla-network.ai) | Characters, voice, image gen, RAG, tools | Companion persona, agents | Persona-led, cluttered |

Takeaway: almost all are "model picker + chat box". None own a daily ritual or connect to personal data. That is Dhruva's open lane.

## 2. Daily assistant / briefing products

- Apple Intelligence (apple.com/apple-intelligence): notification summaries, Priority Notifications/Messages, Mail summaries, Writing Tools (rewrite/proofread/summarize in any text field).
- Google Gemini / Pixel (gemini.google, store.google.com/intl/en/ideas/): Pixel Screenshots (searchable memory of screens), At a Glance, Daily Brief/Magic Cue (proactive cards from Gmail/Calendar).
- Microsoft Copilot Daily (copilot.microsoft.com): audio news-style briefing.
- Superhuman / Shortwave (superhuman.com, shortwave.com): split inbox, one-line summaries per thread, draft-in-my-voice replies, "ask your inbox".
- Reclaim / Motion / Sunsama (reclaim.ai, usemotion.com, sunsama.com): auto time-blocking, guided daily planning ritual, "shut down" review.
- Raycast AI (raycast.com/ai): command palette, reusable AI commands on selected text, quicklinks.
- Notion AI Q&A (notion.com/product/ai): question answering over workspace with sources.
- Rewind/Limitless (limitless.ai): recall over personal history.
- Rabbit / Humane: proactive "what's next" cards; cautionary tale (hardware-led, unreliable, cloud-dependent).

## 3. Ideas worth stealing (idea | why daily | on-device feasibility at 0.5-3B)

1. Morning Brief card (Gemini Daily Brief, Copilot Daily): one glanceable page: today's events, top emails, tasks. Daily open-habit. Feasible: gather data deterministically (calendar query, last-N unread), model only writes 3-5 line prose. Cache overnight via WorkManager. Cloud-free.
2. Per-thread one-line summaries (Shortwave, Apple Mail): scan inbox 10x faster. Feasible: 1-2 sentence summary of truncated body (~1k tokens) fits 1-3B; run lazily on visible rows, cache in local DB. Long threads: summarize last message only.
3. Priority / split inbox (Superhuman, Apple Priority): cut noise. Feasible mostly rule-based (Gmail labels, contacts-known sender, VIP list) + tiny classifier prompt (yes/no urgent). Do not trust the LLM alone.
4. Draft reply in my voice (Shortwave): biggest time saver. Feasible: 3 tone chips (short/warm/formal) from a thread excerpt; user always edits and sends via Gmail intent/API. 1-3B ok for short replies; flaky for nuance, so keep human-in-loop.
5. Notification digest (Apple summaries): tames notification overload. Feasible on Android via NotificationListenerService; batch by app, summarize hourly/evening. Needs special-access permission; process and store locally only; user-excludable apps.
6. Ask-your-stuff over notes/files (Notion Q&A, Enclave): retrieval beats chat. Feasible: on-device embeddings (small MiniLM/bge-small) + SQLite vector index + 1-3B answer with citations. Index size and battery limit it; index when charging.
7. Guided daily plan (Sunsama/Reclaim): morning "pick 3" and evening review. Feasible: mostly UI ritual; LLM only suggests ordering and drafts review text. Auto-scheduling stays rule-based.
8. Writing Tools / Raycast commands everywhere (Apple, Raycast): system share-sheet/selection action "Rewrite, Summarize, Reply". Feasible: Android ACTION_PROCESS_TEXT and share targets; 1-3B is good at rewrite/summarize short text. Highest-reach, low-cost.
9. Saved custom commands (Raycast): user-defined prompts as one-tap buttons ("Turn into todo", "Explain simply"). Trivial and feasible.
10. Proactive cards / Magic Cue (Gemini): surface "meeting in 30 min, here is the thread". Feasible as deterministic triggers (calendar + email subject match) with LLM-written blurb. Skip learned relevance.
11. Pixel Screenshots / Rewind recall: searchable memory. Partially feasible (user-saved notes, shared items only). Continuous capture is out: privacy, battery, trust.
12. Action extraction: events/tasks from email ("Dinner Fri 8pm" -> calendar draft). Feasible with structured JSON/grammar-constrained output; confirm before writing.
13. Privacy ledger / "what left the device: nothing": visible trust surface (Dhruva-specific, differentiator). Fully feasible: per-connector read-only scopes, last-access log, one-tap revoke/wipe.

Not feasible offline at 0.5-3B: long-thread reasoning, multi-step agent planning, reliable web-grounded answers, voice-quality cloning, image understanding at speed on low-end phones. Design around them: deterministic gather, LLM only for short summarize/rewrite/extract, human confirms every write.

## 4. Recommended IA

Principle: open to value, not to a chat box. Chat becomes a tool, not the home.

### Recommended: 4 tabs + persistent Ask
1. **Today**: Morning Brief, next events, priority emails, 3 tasks, notification digest, proactive cards. Default landing.
2. **Inbox**: connector feed (Gmail threads w/ summaries, priority split, draft reply; later other sources). Source filter chips.
3. **Ask**: chat + ask-your-stuff (notes/files/mail/calendar sources with citations), saved commands, history.
4. **Library**: Notes/files folder, saved items, extracted actions/tasks.
Top-right/Settings sheet: Connectors (add/revoke, scopes, privacy ledger), Models (download, benchmark, RAM fit), Privacy, Appearance.
Global: share-sheet/process-text actions; home-screen widget showing Brief.

### Alt A: Chat-first with context shelf (lowest risk)
Tabs: Chat | Brief | Connectors | Models. Keeps current mental model for existing 100+ users; Brief and connectors are added surfaces. Weaker daily habit since chat is still home.

### Alt B: Command-palette / Actions-first (Raycast-like)
Single home: search/command bar + a stack of cards (Brief, quick actions: Summarize inbox, Reply, Plan day, Ask notes). Tabs reduced to Home | Activity | Settings. Fast for power users; steeper discoverability for casual users and heavier to build.

### Migration notes
- Keep model manager reachable (Settings > Models); first-run wizard picks a model by device RAM so users never see a model zoo.
- Onboarding: connect 1 source (calendar is zero-friction, no OAuth) -> instant first Brief = first-run value in <60s.
- Every connector read-only by default; writes (calendar event, send reply) require explicit confirm.
