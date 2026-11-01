# Dhruva app: screen and route map (current state)

Root: `/Users/ansh/engineering/Dhruva/dhruva-app/app/lib`
Source of truth for routes: `core/router/app_router.dart`. Shell: `core/router/app_shell.dart`.
Line numbers are from grep/sed reads on 2026-11-01. Entries marked "verify" were not fully read.

## 1. Navigation structure

- **Bootstrap** (`main.dart:23-47`): reads the onboarding-done flag once on cold start. If not done, `appRouter.go('/onboarding')`. Otherwise the app opens `/chat` (`initialLocation`).
- **Bottom nav** (`app_shell.dart:144-178`, `NavigationBar`), 5 branches in an `IndexedStack`:
  1. **Chat** (`/chat`), icon `chat_bubble_outline`
  2. **Characters** (`/characters`), icon `theater_comedy_outlined`
  3. **Models** (`/models`), icon with a `Badge` (`app_shell.dart:154-165`). The badge shows active downloads.
  4. **Playground** (`/playground`), icon `science_outlined`. Labelled with a lab-flask metaphor.
  5. **Settings** (`/settings`)
- **Shell-level side effects** (`app_shell.dart:52-130`): when a download completes, a snackbar appears ("X is ready, start chatting", action "Start chatting"). It invalidates the installed-model providers.
- **Full-screen routes outside the shell**: `/chat/:id`, `/chat/new`, `/workflows`, `/characters/new`, `/characters/:id`, `/characters/:id/edit`, `/onboarding`, `/models/repo/:id`, `/models/hub`, `/models/search`, `/models/downloads`, `/settings/safety`, `/settings/crash-reports`, `/settings/about`, `/voice/handsfree`.
- **Risk to verify**: `app_router.dart:90-96` and `:210-213` document a 0.6.0 bug where pushing the shell's `/models` from inside a route built a second shell whose Models branch rendered blank. Still-live calls to `context.push('/models')` exist at `conversation_list_screen.dart:49`, `:76`, `settings_screen.dart:92`, and `playground_screen.dart:234` (uses `go`). The safer route `/models/hub` is used elsewhere.

## 2. Onboarding flow (`features/onboarding/ui/onboarding_screen.dart`, state in `state/onboarding_controller.dart`)

Enum `_Step { welcome, pick, download, ready }` (line 32). Single route `/onboarding` (`app_router.dart`).

1. **Welcome** (`_WelcomeStep`, line 192). Title "Welcome to Dhruva". Body "A private AI that runs entirely on your phone." Tagline "Your AI. Your phone. Nobody else's business." Buttons: **Get started** (to pick, line 243), **Skip for now** (line 249, calls `_finish`, marks complete, `context.go('/chat')`, no model).
2. **Pick** (`_PickStep`, line 258). Title "Pick your first model". Copy: "One tap downloads it, Dhruva picks the right size for your phone." A recommended `_ModelOption` (line 355) with a `Recommended` badge (line 471). Tier labels from `ModelTier`: "Runs great", "Should run", "May be slow" (line 725-727). Buttons: **Download {name}** (line 339), **Skip for now** (line 345).
3. **Download** (`_DownloadStep`, line 498). Status texts "Getting X ready", "Preparing…", "This model may be heavy". Error branch: "Download didn't finish", with buttons **Download anyway** (560), **Pick a smaller model** (566), **Try again** (574), **Pick another model** (580). Working branch has a **Cancel** (line 618), which returns to pick.
4. **Ready** (`_ReadyStep`, line 626). "You're ready" with "Try asking" and `_SuggestedPromptChip` rows (line 687) using `_suggestedPrompts` (line 27). Button **Start chatting** (line 678) calls `_startChat`, which marks complete, `go('/chat')`, then pushes `/chat/new` with the installed model id.
- Back gesture is intercepted by `PopScope` (line 120-135) and walks back one step. Download-step back cancels the download.
- Auto-advance: download to ready when the controller reports `installed` (line 109-115).

UX problems: 4 steps before the first chat. There is no "why" for the model choice beyond tier labels. Download is blocked on Wi-Fi/size with no explanation shown. Skip leads to an empty chat list with no model and no nudge until the user taps Chat. The `_SuggestedPromptChip` interactivity should be verified; the chips may be display-only, so the "Try asking" affordance may be a dead end.

## 3. Screens by route

### Chat tab: `/chat` → `ConversationListScreen` (`features/chat/ui/conversation_list_screen.dart`)
- File: `conversation_list_screen.dart:30` (class), `:108` AppBar "Chats".
- **What the user does**: sees folder chips, a list of conversations, starts a new chat, talks hands-free, opens workflows, searches chats.
- **Widgets**: AppBar actions: **Talk** (`record_voice_over_outlined` + label, line 113-118), Workflows icon (line 121-123), search (`ChatSearchAction`, `chat_search_screen.dart:18`). Folder chips (`_FolderChip`, line 261) with a "+" to create folder (`_createFolder`, line 239 dialog "New folder"). `_ConversationBody` (line 155). `ConversationTile` (`widgets/conversation_tile.dart:18`). FAB **+** (line 147).
- **Entry points**: shell tab; from the snackbar after a download; from onboarding's Ready step (sends user to `/chat` then `/chat/new`); from the Talk button.
- **States**: loading `DhruvaLoader` (line 139); error `ErrorStateView` with retry (line 137-141); empty via `NoModelInstalledView` ("No model installed yet" → **Browse models**, `empty_states.dart:32-68`) when no model; `NoConversationsView` ("Start your first conversation" → **New chat**, `empty_states.dart:362-403`) when models exist but no chats.
- **Dead end / flow**: tapping New or Talk with no model shows a snackbar "Download a model to start chatting." and pushes `/models` (line 45-49). Snackbar and navigation happen together, and the user may not read the snackbar.
- **UX problems**: three ways to start a chat (FAB, Talk, empty-state New chat). The "Talk" label is ambiguous. Folder chips are unexplained. Jargon "Workflows" as a shortcut. The conversation list has no sort or bulk actions.

### Chat thread: `/chat/:id`, `/chat/new` → `ChatThreadScreen` (`features/chat/ui/chat_thread_screen.dart`)
- Class `:32`. AppBar `:160`. Title row with `ModelChip` (line 178) or `_CharacterAppBarTitle` (line 171, links to `/characters/:id`).
- **What the user does**: sends prompts (Composer), reads streamed replies, edits and resends messages, copies or shares, exports Markdown or JSON, reports a reply, changes model, opens sampling settings, starts hands-free voice, attaches images, runs a workflow strip.
- **Widgets**: `Composer` (`widgets/composer.dart:35`) with tooltips "System prompt & sampling", "Attach image", placeholder "Message Dhruva…", disclaimer "AI can be wrong. Everything runs on your phone."; `MessageBubble`; `ReasoningBlock`; `ChatErrorCard` (`widgets/chat_error.dart:85`) with copy: "This model needs more memory…" + "Try a smaller model" / "Retry anyway"; `WorkflowStrip` (`widgets/workflow_strip.dart:12`) with chips Summarize, Translate, Rewrite, Draft a reply, Read a document, All; `PopupMenuButton` Export as Markdown / JSON (line 198-205); "New message" scroll-to-bottom FAB (line 314); `ReportSheet` (`widgets/report_sheet.dart:42`).
- **Entry points**: chat list tile, New chat, `/chat/new?characterId=` from character detail, `/chat/new?prompt=` from onboarding or workflows, the snackbar CTA, the Downloads "Start chatting" button, hands-free, search results.
- **States**: loading `DhruvaLoader` (line 124); error via `ErrorStateView` (line 125-130). Empty thread shows `SuggestedPrompts` (`empty_states.dart:84`, "Ready when you are", "SUGGESTED", vision hints) or `NoModelInstalledView` if no model. Per-message error card (`ChatErrorCard`). Message status error (line 355).
- **Dead end**: `_pickModel` (line 440) opens `ModelPickerSheet`. The model chip is tappable, but the chip label reads "Pick a model" when none is loaded (line 329 comment).
- **UX problems**: the AppBar is dense (model chip, Talk icon, export menu, character title). Jargon in the sampling sheet (Temperature, Top-P, Top-K, Context length, `system prompt & sampling`, `sampling_settings_sheet.dart:101-156`). Error copy mentions "memory" without action guidance beyond two buttons. Hands-free opens a separate full-screen route, so the user leaves the thread.

### Chat search: `ChatSearchScreen` (`features/chat/ui/chat_search_screen.dart:33`)
- Route: pushed from `ChatSearchAction` (tooltip "Search chats", line 25). Not a go_router route.
- Search field hint "Search chats" (line 71), clear button (line 78). Results list titles "Untitled conversation" fallback (line 105). Empty "No chats match" (line 93). Error `ErrorStateView` (line 128).
- **UX problems**: no initial state or recent chats before typing. Results show no snippet context beyond the title/line when available.

### Model picker sheet: `features/chat/ui/model_picker_sheet.dart`
- Bottom sheet "Choose a model" (line 69), list tiles with quant and size (line 174-179). Empty "No models installed yet." (line 135). Link "Want to chat about photos? Browse vision models →" to `/models/hub` (line 99-104).
- **UX problems**: "quant" and "unknown quant" jargon shown to end users. Empty state gives no action.

### Characters tab: `/characters` → `CharactersGalleryScreen` (`features/characters/ui/characters_gallery_screen.dart`)
- Class `:23`, AppBar "Characters" `:32`. Import icon (tooltip "Import a character card", line 35-40): "Import JSON card" / "Import PNG card". FAB **Create** (line 54-56).
- **States**: error `ErrorStateView` (line 47). Empty (line 113-143): "No characters yet", "Create a persona to chat with, or import a character card.", button **Create a character**.
- **Entry points**: shell tab. Tile (`widgets/character_tile.dart:11`) → `/characters/:id`.
- **Flow**: import shows `ImportPreviewDialog` (`widgets/import_preview_dialog.dart`, Cancel / Import) then a snackbar; file read errors show "Could not read that file: …" (line 98).
- **UX problems**: "character card" and "persona" are jargon for a general user. Two import formats are exposed as a menu, not as one "Import" action.

### Character detail: `/characters/:id` → `CharacterDetailScreen` (`character_detail_screen.dart:27`)
- AppBar with Export (line 73), overflow menu Edit / Delete (line 81-82), and "Duplicate to edit" for built-ins (line 87-89).
- Body: name, Built-in chip (line 118), **Chat with {name}** button (line 131-133, pushes `/chat/new?characterId=`), sections Persona, Greeting, Example dialogues, Sampling defaults (line 150-154, raw "Temperature 0.7, Top-P …").
- **States**: not found (line 40), loading, error via `ErrorStateView` (line 47-52).
- **UX problems**: Sampling defaults shown as raw numbers. Export has two formats with no explanation. Delete confirm dialog text at line 190.

### Character form: `/characters/new`, `/characters/:id/edit` → `CharacterFormScreen` (`character_form_screen.dart:33`)
- AppBar "New character" / "Edit character" (line 146). Save button disabled until valid (line 149). Fields: Name (hint "e.g. Coach", line 190), Persona (system prompt, line 201, hint "You are ... Speak in a ... tone"), Greeting (optional, line 214), Example dialogues (add/remove, line 220-252), Default model (`_ModelDropdown`, line 365, "None" option, line 387, and "No models installed yet" line 406-411), Override sampling defaults (line 264).
- Avatar: "Choose emoji", "Choose image" (line 173-178).
- Built-in characters redirect to `_BuiltInBlockedView` (line 424): "Duplicate to edit".
- **UX problems**: "Persona (system prompt)" and "Example dialogues" are technical. The dropdown with no models links to the Models tab only in text, not as a button.

### Models tab: `/models` → `ModelsHubScreen` (`features/models_hub/ui/models_hub_screen.dart:37`)
- `DefaultTabController` length 3 (line 39-70). AppBar "Models" (line 53), Downloads icon with tooltip "Downloads" (line 57-58, to `/models/downloads`).
- Tabs: **Discover** (`CuratedTab`, `widgets/curated_tab.dart`, the phone-verified catalog), **Installed** (`_InstalledTab` line 260), **Voice** (`_VoiceTab` line 82).
- Discover: curated cards (`widgets/curated_model_card.dart`), search via `/models/search` (AdvancedSearchScreen).
- Installed: "Import .gguf file" (line 298), empty "No models installed yet. Pick one from Discover or import a local GGUF." (line 331-332), list tiles with Chat (line 359) and Delete (line 364). Delete confirm (line 384-396). Import duplicate dialog "Model already imported" with Skip / Replace (line 416-428). Import progress with Cancel (line 473).
- Voice: `_VoiceBundleCard` (line 130). Title "Hands-free voice", "Install voice bundle" (line 250), "Go to Chats to talk" (line 222). Roles "Turn-taking (required)", "Speech-to-text", "Text-to-speech voices" (line 119-121).
- **States**: error via `ErrorStateView` (line 110, 268), empty installed state (line 326).
- **UX problems**: "GGUF", "quant", "VAD", "ASR", "TTS" are jargon. Tab labels are fine but Downloads is hidden behind an icon. The Installed tab mixes import (technical) with the primary list.

### Model detail: `/models/repo/:id` → `ModelDetailScreen` (`features/models_hub/ui/model_detail_screen.dart:34`)
- AppBar with repo id as title (line 42). Sections: "License & access" (line 71), gated-repo warning "This repo is gated on Hugging Face…" (line 87-96), "Recommended download" card (line 133-203) with "May be slow on your device", "All quantizations (advanced)" (line 236-250, file list), quant tiles with **Download** (line 478-482) or "Installed" (line 466), "Requires Hugging Face sign-in — not supported yet" (line 395).
- States: error via `ErrorStateView` (line 45), "No recognizable GGUF quant files in this repo." (line 105).
- **UX problems**: raw repo ids as the title. Quant file names and sizes are technical. Gated repos are dead ends with no path forward.

### Advanced search: `/models/search` → `AdvancedSearchScreen` (`advanced_search_screen.dart:23`)
- AppBar "Search Hugging Face" (line 29). Hint "Search GGUF models on Hugging Face" (line 94). Disclosure "GGUF models only; very large ones are hidden…" (line 123-125).
- Empty: "Search Hugging Face for a phone-runnable GGUF model." or "No phone-runnable models found…" (line 163-165). Load-more error with "Tap to retry" (line 185-186). Error `ErrorStateView` (line 140).
- **UX problems**: "phone-runnable" and "GGUF" need explanation. Results list has no filter.

### Downloads: `/models/downloads` → `DownloadsScreen` (`features/models_hub/ui/downloads_screen.dart:21`)
- AppBar "Downloads" (line 29). Sections: active (empty "No active downloads.", line 69-72), **Ready** with "Start chatting" (`_ReadySection` line 116, `_ReadyTile` line 177-210), failed with **Retry** and Dismiss (line 220-266), completed "Installed" with "Nothing installed yet." (line 274-285). Error `ErrorStateView` (line 46).
- Entry: Models AppBar icon only (`models_hub_screen.dart:57`), and the Models badge.
- **UX problems**: hidden behind an icon. The "Ready" section is a good handoff. Failed tiles have an unlabelled Dismiss icon (tooltip only).

### Playground tab: `/playground` → `PlaygroundScreen` (`features/playground/ui/playground_screen.dart:27`)
- AppBar "Playground" (line 36). Tabs **Playground** and **AI news** (line 45-50).
- Playground tab: "A / B" chip (line 72), install prompt `_InstallMorePrompt` (line 143) with a hard-coded preview ("Llama 3.2 1B", "Qwen2.5 1.5B", line 208-224) and **Browse models** (line 234, `go('/models')`). Compare body (line 344): "One prompt, two models…", prompt field "Ask both models the same thing…", sliders Temperature, Top-P, Max tokens (line 436-456), **Run on both** / **Stop** (line 468-481), results cards with statuses "Waiting its turn…", "Loading model…", "Fastest" badge (line 704-727). Error card "Could not read installed models." with Retry (line 128-131).
- AI news tab: "Load" button (line 813), "Retry" (line 821), digest "This week in on-device AI" (line 904-909), opt-in fetch from Hugging Face on tap.
- **UX problems**: most important-sounding tab for the least common action. Temperature and Top-P are jargon. The AI news tab mixes a marketing-style digest into a utility app.

### Settings tab: `/settings` → `SettingsScreen` (`features/settings/ui/settings_screen.dart:20`)
- AppBar "Settings" (line 27). Sections: Storage (`_StorageTile` line 73, "Installed models" → `/models`, subtitle from storage summary, error "Couldn't read storage usage"), Safety (`_SafetyTile` line 175, "Safety & reports"), About (`_AboutTile` line 252, "About Dhruva AI", version). `_ClearHistoryTile` (line 97-172) with two confirm dialogs "Clear all chat history?" and "Are you sure?" (the second button is red). `_UpdateTile` (line 206-250) with states "Update available", "Downloading update…", "Update ready. Tap to restart", "Update failed. Tap to retry", "Up to date". `_CrashReportsTile` (line 190, "Crash reports").
- **UX problems**: "Installed models" as the only storage control, with no delete action here. Update tile labels are fine. The About row carries marketing copy.

### Safety & reports: `/settings/safety` → `SafetyScreen` (`features/settings/ui/safety_screen.dart:18`)
- AppBar "Safety & reports" (line 30). Intro copy (line 36-39). "Your reports" list (line 44-62, "No reports yet.", "Couldn't read your reports."), delete per report (tooltip "Delete report", line 135). "Contact developer" mailto (line 75-83).
- **UX problems**: "Models can be wrong… offensive or unsafe text" is clinical. Report list has no detail view.

### Crash reports: `/settings/crash-reports` → `CrashReportsScreen` (`features/settings/ui/crash_reports_screen.dart:9`)
- AppBar with icon actions Share, Email developer, Delete all (line 23-38, keys `crash-share-all`, `crash-email-all`, `crash-delete-all`). Intro "Crash reports stay on your phone…" (line 49). Empty "No crash reports." (line 56). Detail view in monospace SelectableText (line 114-118).
- **UX problems**: developer-facing. Monospace stack dump is not for the user.

### About: `/settings/about` → `AboutScreen` (`features/settings/ui/about_screen.dart:31`)
- AppBar "About" (line 39). Name "Dhruva AI", version, pull-quote block (line 22-28, manifesto copy), "The developer" (line 81-86, "Built by Ansh Singh Rajput under Appu Inside Engineering, building in public…"), links Source on GitHub, Website, Apache License 2.0 (line 96-102). Zero telemetry statement (line 108-111).
- **UX problems**: long branding copy. This is the app's only place for "Why trust this app", but it is hidden under Settings.

### Hands-free voice: `/voice/handsfree` → `HandsFreeScreen` (`features/voice/ui/handsfree_screen.dart:31`)
- Pushed from Chats "Talk", thread AppBar mic icon (`chat_thread_screen.dart:194-196`), and `voice_launch.dart:47`. Full-screen. AppBar "Hands-free" with exit tooltip "Exit hands-free" (line 82-86).
- Phase labels: "Listening…", "Thinking…", "Speaking…", "Starting…", "Voice models needed", "Microphone access needed" (line 229-234). Hints "your turn — speak now", "speak to interrupt" (line 247-249). Animated orb `_VoiceOrb` (line 258) and waveform (line 368). Trust mark "STT + TTS on-device" (line 498-511). "End hands-free" button (line 215-217).
- States: `_NoModelView` (line 522-569) with **Set up voice** (goes to `/models/hub?tab=voice`) and **Already installed? Try again**. `_PermissionDeniedView` (line 577-610) with **Close** and no link to OS settings. `errorMessage` text (line 200-207).
- **UX problems**: "STT + TTS" is jargon. The permission view says "enable it in your device's app settings" without a button to open them. A voice-only flow with no transcript visible unless the thread is opened.

### Workflows: `/workflows` → `WorkflowsScreen` (`features/workflows/ui/workflows_screen.dart:18`)
- AppBar "Workflows" (line 68). Intro "Pick a task, add your text, and your phone does the rest." or "Text ready. Pick what to do with it." when shared (line 77-80). Shared preview (line 100). Workflow rows (`_WorkflowRow` line 125). Privacy note "Runs on your phone. Nothing is uploaded." (line 203).
- `WorkflowSheet` (line 215): Paste (line 354), Open text file (line 360), "Trimmed to N characters to fit your model." (line 341-342), Run (line 393). Clipboard error "Clipboard has no text." (line 264).
- Entry: Chats AppBar icon, Chat workflow strip, intent inbox via `?text=` / `?id=`.
- **UX problems**: "Workflow" as a feature name is abstract. Two different surfaces (list and sheet) for one action. No history.

### Chat-level and shared sheets
- `SamplingSettingsSheet` (`features/chat/ui/sampling_settings_sheet.dart:38`), title "System prompt & sampling" (line 102), **Reset to defaults** (line 180), **Done** (line 183). Field labels Temperature, Top-P, Top-K, Max tokens, Context length. Validation error shown in red (line 166-171).
- `ReportSheet` (`features/chat/widgets/report_sheet.dart:42`): "Report this reply", reasons list, optional note, **Report** and **Report & email developer**.
- `ImageLightbox` (`features/vision/widgets/image_lightbox.dart`) for attached images (not read in depth).
- `EmojiPickerSheet`, `SamplingEditor` (`features/characters/widgets/`) used by the character form (not read in depth).

## 4. Cross-cutting UX issues
- **Jargon leaks into primary UI**: GGUF, quant, VAD/ASR/TTS, STT, mmproj, Top-P, Top-K, context length, persona, system prompt, character card, Hugging Face, "phone-runnable".
- **Model-first gating**: most entry points (New chat, Talk, Characters chat, Playground compare) check for an installed model and bounce the user to Models with a snackbar. There is no single "get a model" state across the app.
- **Duplicate entry points**: new chat appears as FAB, Talk, and empty-state button. Models hub and shell `/models` both exist.
- **Branding in product copy**: "Your AI. Your phone. Nobody else's business." appears on welcome, empty states, and About. Manifesto pull quote on About.
- **Hidden features**: Downloads (icon only), Safety (Settings only), Crash reports (Settings only), Workflows (icon only), Export (overflow).
- **State coverage is mostly good**: loading, error, and empty states exist on most lists. Gaps: Playground compare has no empty-for-thread state; AI news has an error card with retry; Settings storage shows "Loading…" only.
- **Accessibility**: many icon-only actions rely on tooltips only (Downloads, Delete report, Remove example). Verify semantics labels.
