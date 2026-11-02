---
title: Daily assistant — build plan
status: approved direction (owner, 2026-11-01: "A + B's timeline behind 'See day'", "Approved, start building")
---

# Build plan (0.7a: shell + device connectors + 4 features; 0.7b: Gmail)

Integration branch: `redesign/daily-assistant` (off `main` after PRs #17–#20 land). Every wave
merges into it via reviewed PRs; it reaches `main` only after live verification on Android
emulator + iOS simulator and the final gate.

## Wave 0 — prerequisites on `main`
- Merge #17 (tile/widget), #19 (heat guard), #18 (speed test), #20 (doc chat, schema v6) after CI.

## Wave 1 — foundations (one agent, sequential; everything else builds on it)
1. **Backup lockdown (blocker B1):** `allowBackup=false`, `dataExtractionRules` exclude all;
   iOS exclude DB/index dirs from backup. Test that the manifest flags exist.
2. **Theme:** follow system light/dark (light tokens already exist); Rule 6 platform chrome in
   the theme (Android M3 Expressive pill shapes via shape tokens; iOS translucent-chrome
   approximation for tab/nav bars with reduce-transparency fallback). One `AppIdentity`
   constant for product name/wordmark (rename = one line).
3. **Shell + router:** tabs Today · Inbox (hidden until an inbox source exists) · Ask ·
   Library; Settings reached from Today's gear. Moves with no capability lost:
   Chat → Ask (history, folders, pins, search, threads unchanged), Workflows → Actions (Ask),
   Characters → Personas (Ask), Models + Playground + AI news → Settings › Models,
   share-sheet / PROCESS_TEXT / shortcuts → Actions prefilled (shortcuts gain Today, Ask).
   Out-of-shell routes push full-screen routes only (fixes D14 sweep).
4. **Placeholder surfaces** for Today/Inbox/Library with proper empty states (no dead ends).
5. "What moved" one-time sheet for upgrading users.

## Wave 2 — parallel (separate worktrees, each a PR into the integration branch)
- **2A Connectors data layer:** `data/connectors/` interface; store tables (next schema
  version after doc chat), `SearchIndex` (FTS5 probe → fallback Dart BM25); ledger; sync
  service; Calendar (device_calendar_plus) + Contacts (flutter_contacts) read-only; Folder
  (SAF / iOS bookmark channel, index txt/md/pdf via doc-chat extractor, charging-only batch);
  Notifications (Android NotificationListenerService → file queue → Dart ingest; off by default).
- **2B Settings:** Connectors screen + privacy ledger + revoke flows; About me; Appearance;
  Notifications (brief time); Privacy facts (exact network list); Models section hosting
  existing hub, speed test, compare, AI news, voice.
- **2C Ask:** sources chips (Auto/Mail/Calendar/Contacts/Files/Docs) with grounding through
  `SearchIndex`, source chips under answers, chat settings sheet (plain labels), personas
  chip, D1 (stopped/truncated + Continue), D2 (load-failure copy), D3 (composer clears,
  warm-up phase, timeout), "What can I ask?" empty state, PROCESS_TEXT result back to source app.
- **2D Library:** folder block, documents, saved answers, to-dos (extracted, check-off).

## Wave 3 — needs 2A
- **3A Today:** greeting/date, brief (fact list → numbered citations → tappable phrases;
  cached; regenerate on open >3 h / pull / scheduled), Up next with attendees + Prep,
  Needs you, notifications digest card, quick actions, "See day" timeline (direction B).
- **3B Inbox:** notifications (Android) now; mail rows plug in with Gmail (0.7b); sections,
  chips, lazy one-line summaries (visible rows, cached), thread view, Draft reply (tone chips;
  Copy / Open in Gmail; "Save as Gmail draft" only after Google verification), Add to
  calendar via OS insert screen.
- **3C Onboarding v2:** welcome → model (RAM pick, background download) → connect calendar →
  Today with real events.

## Wave 4 — integration + verification
- Hygiene agent: dedupe helpers created in parallel; registry update.
- Live verify on Android emulator + iOS simulator against comps (every surface, light/dark,
  empty/loading/error/offline/permission-denied states, worst-case data via break-ui).
- Re-audit (target ≥ 34/40) + day walk re-run.
- Final gate: impeccable ×2 (independent), emil-design-eng + apple-design Before/After/Why
  table, `review-animations` (owner-run), code review, security-audit (tokens, exported
  components, intent extras, folder paths, prompt-injection boundary).
- Release 0.7.0: Android Play via API; iOS after 0.6.0 approval. Store text + privacy policy
  updated (exact network list, connectors).

## 0.7b — Gmail (beta)
- Google Cloud project + OAuth clients (owner action: console login), consent screen,
  testing mode with test users; read-only connector; verification submission (needs the
  domain + privacy policy page + demo video).
