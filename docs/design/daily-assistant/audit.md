# Dhruva AI 0.6.1 (Android) — Live UX Audit

Date: 2026-11-01. Build: 0.6.1 (build 104), package `app.dhruva.mobile`, emulator-5554 (Pixel-class, 1080x1920 override), Qwen2.5 0.5B Instruct Q4_K_M installed, voice bundle NOT installed, no characters, 1 chat. No code was changed. Method: adb tap/swipe/screencap, every screenshot viewed before the next action, then the `impeccable` critique rubric (Nielsen 10 x 0-4, personas, cognitive load).

## 0. Evidence provenance and honesty notes (read first)

- Screenshots live in `/Users/ansh/.claude/jobs/b45052a3/tmp/redesign/shots/`. Cited by file name below.
- **The emulator was starved by the host** (host load average 40 to 137 from parallel Flutter test and Android Studio processes; guest load 25 to 44). Result: `system_server` died twice mid-session ("The system died", `Can't find service: window / activity`), repeated "System UI isn't responding" dialogs (I tapped Wait each time, `g01`, `h01`, `h02`, `i01`, `i03`), key events arrived late and garbled (typing "Give me 3 tips" produced `G`, then `TT`; `c02`, `m06`), and one "Dhruva AI isn't responding" ANR (`08_chat_menu`, earlier capture). Latency, jank, motion and tok/s (0.0 to 1.0 tok/s) on this emulator are NOT product evidence. Layout, copy, hierarchy, states and flows are.
- I set `hide_error_dialogs=1` and halved animation scales on the emulator after the 5th ANR dialog (device setting only, app untouched). The app process was later gone with no crash trace; treat that as environment, not an app crash.
- **Seen live this session**: Chat home, an existing chat thread, a new-chat error state, Workflows list and Summarize sheet, Characters (empty), Models Discover / Installed / Voice, Model detail (TinyLlama), Playground (compare preview + AI news), Settings (full scroll), Safety and reports, About. **Seen in earlier captures of the same emulator and app** (`07_picker`, `08_chat_menu`, 11:48): the model picker sheet. **Code-read only (not reached live)**: onboarding, hands-free voice, character create/detail/import, downloads screen, chat search results, report sheet, export, sampling sheet, image attach, advanced HF search. Marked "Code" in the matrix.
- A successful send then complete reply was NOT captured this session. An earlier reply exists (`c01`: user "Explain how a rainbow forms, simply." then "A rainbow forms when sunlight", 1h old, visibly cut off). My own send produced a generating state stuck at "0.0 tok/s" (`c04`, `c05`, `c06`) until the framework died.

## 1. What the app is today (one paragraph)

A private, on-device chat app wrapped in five tabs (Chat, Characters, Models, Playground, Settings). Underneath the chat tab sits a useful but buried toolkit: 12 one-tap text workflows, hold-to-talk and hands-free voice, vision, personas, an A/B model arena, Android share-sheet and text-selection ("Ask Dhruva AI") entry points. It is brand-strong (Pole Star mark, serif titles, gold-on-navy), honest about privacy, and model-first: a user must understand models before they get an assistant. There is no memory, no connector to the user's life (mail, calendar, contacts, files), no proactive behaviour, and no output that leaves the app except copy and share.

## 2. Design Health Score (Nielsen's 10, impeccable rubric)

| # | Heuristic | Score | Evidence (file) | Key issue |
|---|---|---|---|---|
| 1 | Visibility of system status | **3** | Live tok/s ticker and model chip with "Loading..." state (`c03`, `c04`); download badge on Models tab; "Runs 100% on your device" trust line in composer (`c01`); disabled "Check for updates: aren't available in this build" states its reason (`j09`). | Truncated reply "A rainbow forms when sunlight" shows no "stopped/incomplete" marker (`c01`, `07_picker` "A rainbow for"). Generating state sat at "0.0 tok/s" with a stop button and no load/time estimate (`c04` to `c06`). Composer still showed the sent text "G" while generating (`c04`). |
| 2 | Match between system and real world | **2** | Good: "Comfortable", "Runs great on your phone", "Hand-picked... no jargon" (`g04`). Bad: "Q4_K_M" (`07_picker`, `j02`, `i08`), ".gguf" button (`j02`), "All quantizations (advanced)" (`i08`), raw repo id as screen title "TheBloke/TinyLlama-1..." (`i08`), "Whisper Tiny... int8... Hinglish" (`j03`), "A / B" chip (`j04`), "Speech-to-text" vs "Talk" vs "Hands-free", "Characters", "Workflows", "Playground" as nouns. | Jargon leaks into primary flows; three names for voice. The Discover header says "no jargon" while the detail screen is full of it. |
| 3 | User control and freedom | **3** | System back works and preserves the Models tab (`j01`); stop button while generating (`c04`); edit-and-resend pencil under user bubble (`c01`); delete and clear-history behind confirms; download cancel. | No undo (confirm-only) for delete chat / clear history; a truncated reply offers regenerate but not "continue". A new chat in an error state can still take typed text with no way to switch to a working model inline (`m03` to `m06`, chip is the only route). |
| 4 | Consistency and standards | **3** | Strong token system: serif page titles, gold primary pill, navy cards, consistent chips (`g04`, `j04`, `j06`). Material 3 NavigationBar with labels. | Entry-point inconsistency: new chat is FAB + Talk + empty-state button; Characters shows two Create CTAs at once (FAB + pill, `g02`); Talk is labelled but Workflows (sparkle) and Downloads (arrow) and Import (upload) are unlabelled icons (`l01`, `g04`, `g02`); model rows use chat+trash icons side by side (`g04`, `j02`) while detail uses a text Download. Dark theme forced (`ThemeMode.dark`), ignoring system setting. |
| 5 | Error prevention | **3** | Fit verdict chip before download (`g04`), size-gated HF search, gated-repo warning, duplicate-import dialog, double-confirm "Clear all chat history" (Code), recommended file preselected (`i08`). | Playground "PREVIEW" shows invented figures "42 tok/s", "31 tok/s", "Fastest" for models the user does not own (`j04`): reads as measured. Chat and Trash icons adjacent, no labels (`j02`). Re-download offered as the only fix for a 379 MB model with no size/cost warning (`m03`). |
| 6 | Recognition rather than recall | **2** | Labelled bottom nav, quick-workflow chips on home (`l01`), suggested prompts (Code). | Hidden: Workflows (unlabelled sparkle, `l01`), Downloads (icon only, `g04`), Export (overflow), sampling (unlabelled sliders icon, `c01`), folders (bare "+" chip), Safety and crash reports (Settings only). Nothing remembered: no recent files, no last-used workflow, no per-chat model memory, no pinned. User must recall where "summarise this email" lives. |
| 7 | Flexibility and efficiency | **2** | Real accelerators exist: Android share sheet "Dhruva AI", text-selection "Ask Dhruva AI", launcher shortcuts, hold-to-talk, hands-free, quick-workflow chips (Code + `l01`). | No widget, no Quick Settings tile, no default-assistant role, no saved prompts or templates, no default model or default system prompt, no bulk actions, no per-workflow history, no in-place text replacement from PROCESS_TEXT (result lands in Dhruva, not back in the source app). Every session starts cold with the model loading. |
| 8 | Aesthetic and minimalist design | **3** | Cohesive identity: Pole Star mark, serif display type, restrained gold accent, generous spacing, no gimmick gradients (`b01`, `l02`, `j06`). | Home is ~70% empty canvas with a floating FAB mid-screen (`l01`); top bar carries four controls; privacy line repeated up to three times per screen (Workflows page + sheet `l03`, composer line + disclaimer `c01`); About opens on a full-screen manifesto quote that pushes real content below the fold (`k02`); "Recommended" pill sits orphaned above the first card, which is already installed (`g04`). |
| 9 | Error recognition and recovery | **2** | Typed failures map to plain English; retry views exist on lists; crash banner and local crash log (Code). | New-chat error: "Couldn't load this model, the file may be corrupted or an unsupported format" with a single CTA "Re-download" (`m03`), shown for the same file that streamed tokens an hour earlier: names a cause it cannot know and offers no "try again", "free memory" or "pick a smaller model". Stuck generation has no timeout or recovery copy (`c04`). Playground "Browse models" uses a route flagged in code as the 0.6.0 blank-Models bug site (Code). |
| 10 | Help and documentation | **2** | Onboarding with suggested prompts (Code); inline helper copy on Discover, Voice and Workflows ("Pick a task, add your text", `l02`); About + Safety explain trust (`k01`). | No help, FAQ or "what can I do with this" surface. Nothing explains folders, characters, temperature/top-p, quantization, why a model is "Comfortable", or what Workflows are beyond one line. Help is copy on screens, not task-led. |
| | **Total** | **25 / 40** | | **Acceptable: significant improvements needed before users are happy** |

### Cognitive load (8-item checklist, failures flagged)
Failed: (1) single focus on home (four top-bar controls + folder chips + workflow chips + list + FAB + 5 tabs, `l01`); (2) minimal choices at the Discover and Voice decision points and the 5 sampling parameters; (3) progressive disclosure on model detail (quant/license before the CTA, `i08`); (4) working memory (user must remember which tab holds which tool, and re-paste context into every workflow). Passed: chunking, grouping, hierarchy within screens. **4 failures = critical band** at the app-structure level even though each individual screen is clean.

### Anti-pattern verdict (AI-slop test)
Does not read as generic AI output: distinctive brand mark, serif + sans pairing, committed navy/gold palette, honest empty states. Tells present but minor: identical rounded-rect cards on Discover and Workflows (`g04`, `l02`); a manifesto pull-quote screen (`k02`); stacked trust microcopy. Detector scan (`npx impeccable`) not run: target is a native Flutter surface with no markup, so only the LLM review applies.

### Strengths worth carrying into the redesign
1. Honest, device-aware model guidance ("Comfortable" verdict, size, Recommended file one tap away, `g04`, `i08`).
2. OS-level entry points already built (share sheet, text-selection menu, launcher shortcuts): the right seed for a daily assistant.
3. Brand and trust voice (on-device, zero telemetry, no account) is clear and a real differentiator.

## 3. Priority issues (defects, P0 to P3)

| ID | Sev | Defect | Evidence | Fix direction |
|---|---|---|---|---|
| D1 | P1 | Replies can end mid-sentence with no "incomplete / stopped" state and no Continue | `c01`, `07_picker` | Mark truncated or stopped replies; add Continue; surface why (stopped, context, error) |
| D2 | P1 | Model-load failure copy blames the file and offers only a 379 MB Re-download | `m03` | Distinguish corrupt file vs memory vs timeout; primary "Try again"; secondary "Use a smaller model"; Re-download last with size |
| D3 | P1 | Generation can sit at "0.0 tok/s" with the sent text still in the composer, no timeout or progress language | `c04`, `c05`, `c06` (caveat: starved emulator; verify on device) | Clear composer on send; model-loading phase with elapsed time; timeout recovery |
| D4 | P1 | Playground preview shows fabricated speed numbers and a "Fastest" badge for models the user does not have | `j04` | Label as illustration inside the card, or show the user's real measured numbers only |
| D5 | P2 | Model detail title is a raw HF repo id, truncated; license precedes the primary action | `i08` | Human name as title, repo id as caption, CTA first, license in details |
| D6 | P2 | Jargon on primary paths: Q4_K_M, .gguf, quantizations, Temperature/Top-P/Top-K, int8, A / B | `07_picker`, `j02`, `i08`, `j03`, `j04` | Plain-language labels ("Balanced / Smaller / Sharper"); jargon behind "Advanced" |
| D7 | P2 | Hidden primary features: Workflows (unlabelled sparkle), Downloads (icon), Import, Export | `l01`, `g04`, `g02` | Label or promote; Workflows should be the home, not an icon |
| D8 | P2 | Characters empty state has two Create CTAs; no seeded built-ins; "character card"/"persona" jargon | `g02` | One CTA; ship 3 to 5 starter personas; rename to plain words |
| D9 | P2 | Duplicate and stacked trust microcopy (up to 3 per screen); About leads with a manifesto | `l03`, `c01`, `k02` | One trust line per screen; About: version, privacy facts, links first |
| D10 | P2 | Home underuses the screen: 70% empty, FAB floating mid-screen, 4 top-bar controls | `l01` | Make home an "ask / do" surface; move chrome |
| D11 | P2 | Installed row: "1 installed . 379 MB used" collides with the Import .gguf button | `j02` | Stack on narrow widths, 16 px gutter |
| D12 | P2 | "Recommended" pill orphaned above an already-installed model | `g04` | Hide when installed, or bind to the recommended card |
| D13 | P3 | Forced dark theme (light tokens exist); no theme or language setting; Settings has zero real preferences | `j06`, `j09`, code `main.dart:71` | Follow system; add real preferences |
| D14 | P2 | Documented 0.6.0 blank-Models route bug still has live call sites (`context.push('/models')`) | Code: conversation_list_screen.dart:49,76; settings_screen.dart:92; playground_screen.dart:234 | Route everything through `/models/hub` or one navigator helper |
| D15 | P3 | Hands-free permission-denied view has no Open Settings button; onboarding Skip leads to an empty list with no nudge | Code | Add deep link; add inline "pick a model" nudge |
| D16 | P2 | Background generation unsupported (R12): leaving the app mid-reply loses or stalls the answer | Code/docs roadmap | Foreground service or resume UX; tell the user |

## 4. Persona red flags

**Riley, the daily-assistant user (project persona: wants one place for mail, calendar, notes, quick writing, uses it 10 times a day).** Opens the app: lands on a chat list, not on "what can I do". To summarise an email they must leave Dhruva, copy, return, tap sparkle, tap Summarize, Paste, Run, then copy the result back (`l01`, `l02`, `l03`). It does not know the date, her calendar, her contacts, or what she asked yesterday. Abandons after day 3 for the assistant that can already see her inbox.

**Jordan (first-timer).** Splash, then a model-first journey: "Recommended", "Comfortable", "379 MB", "Q4_K_M" (`g04`, `i08`). Icon-only Workflows, Downloads, Import. Cannot tell "Characters" from "Chat", or what "Playground / A / B" is (`j04`). Will not find Workflows.

**Alex (power user).** Likes the share sheet and "Ask Dhruva AI". Misses: default model, saved prompts, quick tile, widget, history of workflow runs, result replacing selected text in place, any bulk or keyboard path, batch import.

**Sam (low-end phone, patchy data, Hindi/Hinglish).** Model-load errors blame the file (`m03`); 111 MB speech model with no data estimate (`j03`); UI is English-only; devanagari font fallback exists but UI copy is not localised.

## 5. WORKFLOW WALK: a realistic day with someone who wants a daily assistant

Persona: Riley, 31, product manager, Android phone, 6 GB RAM, patchy mobile data on the commute, privacy-minded (this is why she installed Dhruva). She wants one assistant she uses all day. Legend: **[LEAVE]** has to leave the app; **[GUESS]** has to guess or hunt; **[RETYPE]** has to re-enter something the phone already knows or she already said; **[NONE]** no capability exists at all.

### Morning (7:40, commute, one hand, standing)
1. Wakes the app. Cold start shows the Pole Star splash, then a chat list with one old chat "Explain how a rainbow forms, s..." (`l01`). The model is not loaded: the chip says "Loading..." until she sends (`c03`). **[GUESS]** nothing tells her it is ready.
2. Wants "What is on my day?" There is no calendar, no email, no date awareness. **[NONE]** (G1, G2). She opens Calendar, reads, then **[LEAVE]** to copy event text, **[RETYPE]** into Workflows via sparkle, Paste, Summarize (`l02`, `l03`). That is 7 taps and two app switches for what a connector would do in 0.
3. Wants a spoken briefing hands-free while walking. "Talk" exists but the voice bundle (3 models, 111 MB+) is not installed, so the first attempt dead-ends into Models > Voice (`j03`, Code). **[GUESS]** why Talk did not talk. No proactive morning briefing, no notification at a set time. **[NONE]** (G4).
4. A WhatsApp message needs a reply. Select text, "Ask Dhruva AI" works (manifest PROCESS_TEXT). It opens Workflows prefilled. She taps "Draft a reply", Run, waits at 1 to 5 tok/s on a 0.5B model, then must **[LEAVE]** back to WhatsApp, long-press, paste. The result cannot replace the selected text in place. **[RETYPE]**.
5. Asks the app to "remind me to call the vet at 5". **[NONE]**: no tools or actions (G3), the Toolbox is only on the roadmap.

### At work (10:00 to 17:00, desk, two monitors worth of tabs)
6. A 14-page PDF arrives. "Understand a document" accepts only a pasted or opened **text** file; PDF, Docs, Sheets, images of slides are unsupported. **[NONE]** (G5, RAG planned not built). **[LEAVE]** to a PDF reader, select, copy, back.
7. A long email thread: share-sheet text arrives, but a 0.5B/1B model's context truncates silently apart from one notice ("Trimmed to N characters", Code). She cannot tell what was dropped. **[GUESS]**.
8. "Draft a reply" every time **[RETYPE]** her role, tone, signature, company vocabulary: there is no memory, no default system prompt, no "about me" (G6). A Character could hold a persona but Characters is a separate tab and workflows cannot use one (`g02`, Code). **[GUESS]** which surface to use.
9. Needs the answer in Gmail. Only Copy per reply and share-whole-chat export exist. No "send to Gmail / Notes / Keep". **[LEAVE]**.
10. Compares two models for quality: Playground needs a second model; with one installed she sees fabricated preview numbers (`j04`). **[GUESS]** what is real.
11. Switches to a larger model for harder tasks: picker shows "Q4_K_M . 379 MB" (`07_picker`). **[GUESS]** which is better; no "good for writing / good for summaries" labels beyond Discover blurbs (`g04`).
12. Locks the phone mid-generation; a reply may stall or be lost (R12). On return the reply can be cut off with no marker (`c01`). **[RETYPE]** the question.

### Evening (21:30, sofa, charging, relaxed)
13. Kid's homework: "Explain simply" and "Quiz me" exist (workflow catalog). Good. But each is a one-shot sheet; no "keep going" thread with the same persona without leaving Workflows for Chat. **[GUESS]**.
14. Wants to find the chat from this morning. Title is the first line truncated; no summaries, pins surfaced, or date sections; search is by text (`l01`). **[GUESS]**.
15. Wants a "daily recap and plan for tomorrow". No day timeline, no notes, no tasks, no journal, nothing it remembers from the day. **[NONE]** (G6, G7).
16. Wants it on her laptop too, or to back up before changing phones. No sync, no export-all, no backup. Reinstall loses everything. **[NONE]** (G9).
17. Photo of a whiteboard: needs a separate 2.2B vision model, offered only via a link in the picker ("Want to chat about photos? Browse vision models", `07_picker`). **[LEAVE]** to Models, **[GUESS]**.
18. Sets up before bed: wants to know battery and heat cost of on-device inference. Nothing. **[NONE]**.

### Count
Of 18 steps: **7 [LEAVE]**, **7 [GUESS]**, **5 [RETYPE]**, **6 [NONE]**. The day is survivable only as a clipboard relay between Dhruva and other apps.

## 5b. Capability gaps (things that do not exist; not defects)

| ID | Gap | Why a daily user needs it | Existing seed to build on |
|---|---|---|---|
| G1 | Connectors: Gmail (read/search/draft), Google Calendar, device calendar, contacts | "What is on my day / who is this / reply to this" without copy-paste | `INTERNET`, intent inbox; no permissions held today |
| G2 | Awareness of now: date, time, location, weather, battery, focus mode | Basic grounding for every answer | none |
| G3 | Tools and actions via tool-calling: reminders, alarms, notes, calculator, send, open app | Assistant acts, not just talks | roadmap loop 10 "Toolbox" |
| G4 | Proactive and scheduled: morning briefing, evening recap, reminders, notification with reply | Habit loop | download notifications only |
| G5 | Documents and files: PDF, Docs, images, folder watch, on-device RAG | Work reality | roadmap loop 9; `file_selector`, "Open text file" |
| G6 | Memory: facts about the user, preferences, per-project context, long-term chat recall | Stop re-explaining | Characters have per-character memory (code docs) |
| G7 | Notes, tasks, journal surface | Place for outputs | none |
| G8 | Output to other apps: send to Gmail/Keep/Notes, replace selected text in place (PROCESS_TEXT result), share a single reply | Close the loop | `share_plus` on exports only |
| G9 | Backup, restore, export-all, multi-device sync (optionally end-to-end) | Trust before daily reliance | per-chat Markdown/JSON export |
| G10 | Android assistant role / widget / Quick Settings tile / lock-screen entry / wake word | One-gesture access | launcher shortcuts, PROCESS_TEXT, SEND |
| G11 | Background inference with foreground service and resume | Real-life interruptions | R12 |
| G12 | Saved prompts, workflow history, user-defined workflows, per-workflow defaults | Efficiency | 12 fixed workflows |
| G13 | Model auto-selection ("fast now, smart when charging"), per-task model, auto model warm-up | Hides model-first friction | model tiers |
| G14 | Settings with real preferences: default model, theme (system/light), language and Hindi UI, notifications, data, voice | Basic control | light tokens in code, Devanagari font |
| G15 | Help: task-led tips, "what can I ask", capability discovery | Discoverability | onboarding suggested prompts |
| G16 | Cloud-escape hatch (optional, explicit) for heavy tasks | Small on-device models fall short | none (privacy position) |

## 5c. Capability vs defect, in one line each
- **Defects** (D1 to D16, section 3) are things the app tries to do and does badly: truncated replies, misleading error, fabricated preview numbers, jargon, hidden features, clutter.
- **Gaps** (G1 to G16, above) are things a daily assistant must do that the app cannot do at all. The redesign must treat G1 to G4 and G6 as architecture, not decoration.
## 6. Feature-parity matrix (everything the 0.6.1 app does; a redesign must not drop any)

Source: route map (`screens-map.md`), code reads on 2026-11-01, plus live captures. "Live" = seen on emulator this session; "Code" = read from source only.

| # | Capability | Where it lives today | Evidence | Notes for redesign |
|---|---|---|---|---|
| **Onboarding** | | | | |
| 1 | 4-step first run: welcome, pick model, download, ready | `/onboarding` | Code | Skippable at every step; marks done flag; Ready step offers suggested prompts then `/chat/new` |
| 2 | Tiered model recommendation ("Runs great / Should run / May be slow") | onboarding Pick, Discover cards | Code + Live (Discover "Comfortable") | Device-RAM aware (`device_info_service`, `model_tier`) |
| 3 | Download error recovery (Download anyway / smaller / retry / pick another) | onboarding Download | Code | |
| **Chat** | | | | |
| 4 | Conversation list, relative timestamps, overflow menu per row | `/chat` | Live | "10m ago", kebab menu |
| 5 | Folders (create, filter chips) | `/chat` chips | Live (All + "+") | Conversations.folderId FK; deleting a folder un-files chats |
| 6 | Pinned conversations | DB `pinned` column | Code | UI for pin not verified live |
| 7 | Search chats | `ChatSearchScreen` | Live (icon) + Code | No recent/initial state |
| 8 | New chat (FAB) | `/chat/new` | Live | 3 entry points today |
| 9 | Streaming replies, stop button, live tok/s ticker | `ChatThreadScreen`, `ModelChip` | Live | |
| 10 | Edit and resend a user message | pencil under user bubble | Live | |
| 11 | Per-reply actions: read aloud (TTS), copy, report, regenerate | under assistant bubble | Live | |
| 12 | Markdown + code rendering; collapsible reasoning (`<think>`) blocks | `MessageBubble`, `ReasoningBlock` | Code | |
| 13 | Export chat as Markdown or JSON (share sheet) | thread kebab menu | Code | `chat_export.dart`, `share_plus` |
| 14 | Share chat out | thread menu | Code | |
| 15 | Per-chat System prompt and sampling (Temperature, Top-P, Top-K, Max tokens, Context length), reset to defaults | composer left icon, sheet | Live (icon) + Code | Jargon-heavy |
| 16 | Model chip in thread header; model picker sheet (name, quant, size); link to vision models | thread header | Live (earlier capture 07_picker) | One model installed = a picker with one row |
| 17 | Image attach (vision models), image lightbox | composer | Code | `features/vision`, mmproj pairing |
| 18 | Report a reply (reason + note, optionally email developer) | `ReportSheet` | Code | Local report list in Settings > Safety |
| 19 | "New message" scroll-to-bottom pill | thread | Code | |
| 20 | Trust line "Runs 100% on your device" + "AI can be wrong" disclaimer | composer | Live | |
| 21 | Empty thread: suggested prompts (text + vision hints) | `SuggestedPrompts` | Code | |
| 22 | Generation persists across in-app navigation | engine/chat controller | Code (docs) | NOT true while app is backgrounded (R12) |
| **Voice** | | | | |
| 23 | Hold-to-talk mic in composer (speech to text) | composer | Live | |
| 24 | Hands-free full-screen loop (VAD turn-taking, STT, TTS, interrupt by speaking, orb + waveform) | `/voice/handsfree` | Live (entry) + Code | Needs voice bundle |
| 25 | Voice bundle install/manage (VAD, ASR, TTS voices) | Models > Voice | Code | |
| 26 | Mic permission-denied view | handsfree | Code | No deep link to OS settings |
| **Workflows (one-tap text verbs)** | | | | |
| 27 | 12 workflows: Summarize, Key points, Explain simply, Translate, Rewrite, Fix grammar, Draft a reply, Extract to-dos, Study notes, Quiz me, Social caption, Understand a document | `/workflows`, chat-list strip | Live (strip) + Code | `workflow_catalog.dart` |
| 28 | Input: Paste, Open text file, shared text; auto-trim to model context with notice | `WorkflowSheet` | Code | |
| 29 | **OS integration in:** Android share sheet "Dhruva AI" (text/plain) | manifest SEND filter | Code | Opens Workflows prefilled |
| 30 | **OS integration in:** text-selection menu "Ask Dhruva AI" (PROCESS_TEXT alias) | manifest | Code | Works in every app |
| 31 | Launcher long-press shortcuts | `shortcuts.xml` | Code | |
| **Characters** | | | | |
| 32 | Gallery, create, edit, delete, duplicate built-in to edit | `/characters*` | Live (empty state) + Code | Built-ins "seedBuiltInsIfPresent"; gallery was EMPTY on this install |
| 33 | Persona (system prompt), greeting, example dialogues, default model, sampling override, emoji or image avatar | form | Code | |
| 34 | Import character card (JSON or PNG tEXt chunk) with preview; export | gallery / detail | Code | `png_text_chunk.dart` |
| 35 | Chat with a character (`/chat/new?characterId=`) | detail | Code | Per-character conversation memory |
| **Models** | | | | |
| 36 | Curated Discover catalog (8 phone-verified models), verdict chip, size, Recommended badge, "Larger models" collapsed group | Models > Discover | Live | |
| 37 | Hugging Face advanced search (GGUF only, size-gated), model detail with license, gated warning, recommended file + all quantizations | `/models/search`, `/models/repo/:id` | Live (detail) + Code | Gated repos are dead ends |
| 38 | Download manager: progress ring, ETA/speed, Ready, Failed (Retry/Dismiss), background and notification progress, foreground service, sha256 integrity check | `/models/downloads`, badge | Code | |
| 39 | Installed list: Chat, Delete (confirm), Import local .gguf (duplicate Skip/Replace, cancel) | Models > Installed | Code | |
| 40 | Storage summary | Settings | Code | |
| **Playground** | | | | |
| 41 | A/B compare two installed models on one prompt, sliders, run/stop, "Fastest" badge, install-second-model prompt with preview | `/playground` | Code | |
| 42 | AI news digest (opt-in fetch from Hugging Face) | Playground tab 2 | Code | |
| **Settings / trust / ops** | | | | |
| 43 | Clear all chat history (double confirm) | Settings | Code | |
| 44 | Update tile (Shorebird code-push: available, downloading, ready, failed, up to date) + update banner | Settings, shell | Code | |
| 45 | Safety and reports (local report list, delete, contact developer mailto) | `/settings/safety` | Code | |
| 46 | Crash reports (local only: view, share, email, delete all) + crash banner | `/settings/crash-reports` | Code | |
| 47 | About (version, developer, links, license, zero-telemetry statement) | `/settings/about` | Code | |
| 48 | Forced dark theme (light theme exists in code, `themeMode: ThemeMode.dark`) | `main.dart:71` | Code | No theme setting |
| 49 | Devanagari font fallback | theme | Code | Indic text support |
| **System** | | | | |
| 50 | Download-complete snackbar with "Start chatting" | shell | Code | |
| 51 | Typed failure to friendly message mapping, retry views | `AppFailure`, `ErrorStateView` | Code | |
| 52 | Safety guard on prompts/replies | `safety_guard.dart` | Code | Behaviour not verified live |

Platform permissions held: INTERNET, CAMERA, POST_NOTIFICATIONS, FOREGROUND_SERVICE(_DATA_SYNC). **No** contacts, calendar, SMS, notification-listener, accessibility, or storage-scan permission: confirmed in `AndroidManifest.xml`.
