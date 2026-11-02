# Component Registry — Dhruva (dhruva-app)

Seed registry generated from a read-only map of `app/lib`. Paths are relative to repo root `/Users/ansh/engineering/Dhruva/dhruva-app`.
Status: SEED. "What it is" entries are inferred from class names, file placement, and signatures; each entry needs a visual/behavioral read before a redesign relies on it. Consumer lists are file-level grep results (`grep -rlw ClassName`), excluding the defining file.

> Read before building ANY new UI element. Update at every round close.

## How to use (the non-blind reuse loop)

1. Before creating a component: search here first. Found → read "When NOT to use", then adapt the idea, not a literal copy.
2. Not found here: run one search over `app/lib` to confirm it does not exist, then build.
3. Built something reusable: register it at round close.
4. Copy-with-drift found: log under Extraction Candidates.

## Canonical components

### Shared (`app/lib/core`)

| Component | Path | Use for | When NOT to use | Gotchas / adaptation notes | Used by |
|---|---|---|---|---|---|
| `ErrorStateView` | `app/lib/core/widgets/failure_view.dart` | Full-area error state with retry (`error`, `onRetry`) | Inline field errors; non-retryable notices | Takes raw `error`; maps via `failure_message.dart` | `core/failures/failure_message.dart`, chat screens (conversation_list, model_picker_sheet, chat_thread, chat_search), models_hub screens (advanced_search, models_hub, model_detail, downloads), characters screens (detail, form, gallery) |
| `EmptyStateView` | `app/lib/core/widgets/failure_view.dart` | Empty-list / no-results placeholder | Error states (use ErrorStateView) | Lives beside ErrorStateView; same file | models_hub (advanced_search, models_hub, model_detail), characters (detail, form) |
| `DhruvaStar` | `app/lib/core/theme/brand_star.dart` | Brand mark (pole star), static | As a loading indicator (use DhruvaLoader); decorative clutter | Custom painter `_StarPainter`; brand asset, do not restyle casually | about_screen, model_picker_sheet, chat_thread_screen, chat/widgets/empty_states, voice/handsfree_screen, characters_gallery_screen, characters/state/installed_models_provider, onboarding_screen; also `features/chat/widgets/brand_motif.dart` |
| `DhruvaLoader` | `app/lib/core/theme/brand_star.dart` | Brand-styled loading indicator (StatefulWidget, uses `pulseMedium`/`pulseSlow` motion) | Non-loading states; tiny inline spinners in buttons | Owns its own ticker; pulse durations come from `TokenMotionDuration` | ~18 files: failure_view, chat (conversation_list, model_picker_sheet, chat_thread, chat_search, model_chip), playground_screen, models_hub (advanced_search, models_hub, model_detail, downloads, listing_download_button, voice_model_tile), voice/tts_button, characters (detail, form, gallery) |
| `AppIdentity` | `app/lib/core/identity/app_identity.dart` | Product name, short name, wordmark, tagline: the ONLY place name strings live (rename = one line) | Android label / iOS display name / package ids (stay in platform files until the rename is decided) | Test `app_identity_test.dart` fails if a UI string hardcodes the name | settings, onboarding, crash/safety/report copy, today wordmark |
| `AdaptiveTabBar`, `GlassChrome`, `AdaptiveAppBar`, `ChromeScaffold`, `useGlassChrome` | `app/lib/core/widgets/platform_chrome.dart` | Rule 6 chrome: Android = solid M3 Expressive (pill from theme); iOS = translucent `BackdropFilter` APPROXIMATION of Liquid Glass, chrome only, one layer | Content cards/rows (never glass); glass on glass | Falls back to solid on `MediaQuery.highContrast` or Settings > Appearance "Reduce transparency". Branches on `Theme.of(context).platform` | app_shell, today/inbox/library screens |
| `PressableScale` | `app/lib/core/widgets/pressable_scale.dart` | Press feedback (scale 0.97, 120ms ease-out, on pointer-down) for custom tappable surfaces | Widgets with their own ink (buttons, ListTile) | Wrap the decorated surface; no ripple | today quick actions, library folder row |
| `NextStepCard` | `app/lib/core/widgets/next_step_card.dart` | Empty state card with ONE working primary action ("no dead ends") | Error states (ErrorStateView) | Title + body + action button | today, inbox, library, day timeline |
| `LabelChip` | `app/lib/core/widgets/label_chip.dart` | Small neutral label pill ("Android", an app name), width-capped with ellipsis | A coloured status/time pill (`InfoPill` in Today); a tappable filter chip (Material `FilterChip`) | Replaced two identical private copies (`_AppChip` in Inbox, `_AndroidChip` in Connectors) | inbox, settings/connectors |
| `ModelDownloadLine` | `app/lib/core/widgets/model_download_line.dart` | "Downloading your model · 42%" / "Finishing up…" with bar and transfer line, for surfaces that must say a model is on its way | The model hub's own tiles (`DownloadProgressTile`) | Percent comes from `downloadFraction`, which is null (indeterminate bar) once every byte is here: never shows 100% before the model is registered | today brief card, chat no-model view |
| `downloadFraction`, `downloadFinishing`, `modelDownloadProvider` | `app/lib/core/di/model_download.dart` | The one reading of download progress: fraction while bytes arrive, "finishing" once complete or hashing; the running chat-model download | Voice bundles (ignored by design) | Onboarding's strip and download step read `OnboardingDownloadState.finishing` (same helper) | today, chat, onboarding |
| `shortWhen`, `timeAgo` | `app/lib/core/format/when.dart` | The one "when" label: row timestamps (clock today / Yesterday / weekday / "3 Nov") and conversation age ("5m ago") | Event times in Today (`clock`, `relativeStart`, `ageLabel` in `features/today/state/day_text.dart`: "in 1h 48m", brief age) | `shortWhen` takes the clock formatter so 12/24 h follows the phone. Replaced `inboxWhen`, `ledgerWhen` and two private `_relativeTime`s | inbox, ledger, conversation list, message bubble |
| `PrefsStore` / `prefsStoreProvider` | `app/lib/core/settings/prefs_store.dart` | Tiny persisted key/value (theme mode, reduce transparency, what-moved flag) | Large or relational data (Drift) | One JSON file in app support dir; `MemoryPrefsStore` for tests | appearance_providers, what_moved |
| `themeModeProvider`, `reduceTransparencyProvider` | `app/lib/core/theme/appearance_providers.dart` | Persisted System/Light/Dark and reduce-transparency | | Loaded before first frame in `main()` | main.dart, settings_screen |
| `WhatMovedGate` / `WhatMovedSheet` | `app/lib/core/settings/what_moved.dart` | One-time "What moved" sheet for upgraders from 0.6.x | | Onboarding marks it dismissed so new users never see it | app_shell |
| `inboxAvailableProvider` | `app/lib/core/router/inbox_availability.dart` | Gates the Inbox tab (false until an inbox source is connected) | | Wave 2A/3B overrides it | app_shell |
| `DownloadStatusPill` | `app/lib/features/models_hub/widgets/download_status_pill.dart` | Today header pill while a download runs; opens Downloads | | Injected into Today by the router (ADR-002) | app_router (Today) |

### Chat (`app/lib/features/chat/widgets`)

| Component | Path | Use for | When NOT to use | Gotchas / adaptation notes | Used by |
|---|---|---|---|---|---|
| `TrustMark` | `features/chat/widgets/brand_motif.dart` | Privacy/on-device trust badge | Generic status chips | Brand-voice element | composer, empty_states |
| `TypingIndicator` | `features/chat/widgets/brand_motif.dart` | Assistant-is-generating indicator | Non-generation waiting (use DhruvaLoader) | Motion-driven | chat_thread_screen, handsfree_screen, voice/mic_button |
| `ChatErrorCard` | `features/chat/widgets/chat_error.dart` | Inline error inside a chat thread | Full-screen failures (ErrorStateView) | — | chat_thread_screen |
| `Composer` | `features/chat/widgets/composer.dart` | Message input bar with send/mic | Non-chat text entry | Embeds MicButton and TrustMark | chat_thread_screen, empty_states |
| `ConversationTile` | `features/chat/widgets/conversation_tile.dart` | Row in conversation list | Non-conversation lists | — | conversation_list_screen |
| `MessageBubble` | `features/chat/widgets/message_bubble.dart` | One chat message (user/assistant) | System notices | Embeds ReasoningBlock, TtsButton | chat_thread_screen, chat_controller |
| `ReasoningBlock` | `features/chat/widgets/reasoning_block.dart` | Collapsible reasoning/thinking section in a message | Final answer text | — | message_bubble |
| `ReportSheet` | `features/chat/widgets/report_sheet.dart` | Bottom sheet to report a message (`showReportSheet`) | General-purpose sheets | Entry via `showReportSheet(...)` | chat_thread_screen (opened via `showReportSheet`) |
| `ModelChip` | `features/chat/widgets/model_chip.dart` | Shows active model in chat header | Model picking (use model_picker_sheet) | Also defines `TokPerSecTicker` (live tok/s readout) | chat_thread_screen |
| `WorkflowStrip` | `features/chat/widgets/workflow_strip.dart` | Horizontal strip of workflow/quick actions | — | — | conversation_list_screen |
| `NoModelInstalledView`, `SuggestedPrompts`, `NoConversationsView` | `features/chat/widgets/empty_states.dart` | Chat empty states | Error states | Three empty-state variants in one file | conversation_list_screen, chat_thread_screen, handsfree_screen |

### Models hub (`app/lib/features/models_hub/widgets`)

| Component | Path | Use for | When NOT to use | Gotchas / adaptation notes | Used by |
|---|---|---|---|---|---|
| `CuratedModelCard` | `features/models_hub/widgets/curated_model_card.dart` | Featured model card | List rows (ModelListTile) | — | listing_download_button, curated_tab |
| `CuratedTab` | `features/models_hub/widgets/curated_tab.dart` | Curated tab body | — | Overrides divider color locally (`Colors.transparent`) | models_hub_screen |
| `ModelListTile` | `features/models_hub/widgets/model_list_tile.dart` | Row for a model in lists/search | Featured display (CuratedModelCard) | — | advanced_search_screen, listing_download_button |
| `ListingDownloadButton` | `features/models_hub/widgets/listing_download_button.dart` | Download / progress control for a listing | Non-download actions | Wraps DownloadProgressRing | model_list_tile, curated_model_card |
| `DownloadProgressRing` | `features/models_hub/widgets/download_progress_ring.dart` | Circular progress for downloads | Linear progress | — | model_detail_screen, listing_download_button |
| `DownloadProgressTile` | `features/models_hub/widgets/download_progress_tile.dart` | Downloads-list row with progress | Non-download rows | — | downloads_screen |
| `LicenseChip` | `features/models_hub/widgets/license_chip.dart` | License label chip | — | Same file as `GatedBadge` | model_detail_screen, model_list_tile |
| `GatedBadge` | `features/models_hub/widgets/license_chip.dart` | Badge for gated models | — | Same file as `LicenseChip` | model_detail_screen, model_list_tile |
| `QuantQualityChip` | `features/models_hub/widgets/quant_quality.dart` | Quantization quality chip | — | — | model_detail_screen |
| `ModelVerdictChip` | `features/models_hub/widgets/verdict_chip.dart` | Fit verdict chip for a model | — | — | model_detail_screen, curated_model_card |
| `VoiceModelTile` | `features/models_hub/widgets/voice_model_tile.dart` | Row for voice models | Text models | — | models_hub_screen |

### Characters, settings, voice, misc

| Component | Path | Use for | When NOT to use | Gotchas / adaptation notes | Used by |
|---|---|---|---|---|---|
| `CharacterAvatar` | `features/characters/widgets/character_avatar.dart` | Character emoji/avatar | — | — | chat_thread_screen, character_detail_screen, character_form_screen, character_tile, import_preview_dialog |
| `CharacterTile` | `features/characters/widgets/character_tile.dart` | Character gallery tile | — | — | characters_gallery_screen |
| `SamplingEditor` | `features/characters/widgets/sampling_editor.dart` | Sampling-parameter editor | Generic settings | — | character_form_screen |
| `emoji_picker_sheet` (class in file) | `features/characters/widgets/emoji_picker_sheet.dart` | Emoji picker sheet | — | Uses hardcoded `fontSize: 26` | — (not verified in grep) |
| `import_preview_dialog` (class in file) | `features/characters/widgets/import_preview_dialog.dart` | Preview before importing a character | — | — | — |
| `CreditRow` | `features/settings/widgets/credit_row.dart` | Settings credit line | — | — | settings_screen, about_screen |
| `VersionText` | `features/settings/widgets/version_text.dart` | App version label | — | — | settings_screen, about_screen |
| `SettingsPage`, `SettingsGroup`, `SettingsRow`, `SettingsSwitchRow`, `SettingsSectionLabel`, `SettingsNote`, `SettingsIconTile` | `features/settings/widgets/settings_widgets.dart` | Every Settings screen: ChromeScaffold + big serif title + grouped rounded rows with icon tile, one-line description (Connectors comp language) | Content screens outside Settings | Switch rows disable (not mis-render) while the saved value loads. Tests find the inner `SwitchListTile` with `find.descendant` | settings_screen, about_me, privacy, notifications, appearance, about |
| `ClearHistoryRow`, `UpdateRow` | `features/settings/widgets/clear_history_row.dart`, `update_row.dart` | Clear-all-history (two confirmations; on Privacy) and Check-for-updates (on About) | — | Moved out of the old Settings list unchanged | privacy_screen, about_screen |
| `UserProfile`, `buildUserContext`, `userContextProvider` | `core/profile/user_profile.dart` | About me data + THE one prompt-context builder ("About the user" block, non-empty fields, capped 600 chars). Ask/Actions get it via ChatController; drafts (Wave 3) must call the same builder | A second ad-hoc profile string in a prompt | Empty profile = '' (nothing added) | chat_controller, about_me_screen |
| `SearchInChips`, `askChips`, `AskSourceSelection`, `askSelectionProvider` | `features/chat/widgets/search_in_chips.dart`, `data/connectors/ask_sources.dart`, `features/chat/state/ask_selection.dart` | Ask's "Search in" row: Auto (rules) / pinned sources, unconnected = "Connect" (opens `/settings/connectors?connector=<id>`), Mail hidden until a mail connector exists | Anything outside Ask | Selection lives in a provider keyed by `ChatRouteArgs`, not in `ChatThreadState`. Auto rules are pure (`autoSelectSources`) | chat_thread_screen |
| `AnswerSourceChips`, `showSourceSheet` | `features/chat/widgets/answer_source_chips.dart` | "Sources" chips under a grounded answer + the item detail sheet (event, notification, file, contact) | Document page citations (`SourcesBlock`) | Item text is plain `Text`, never linked or acted on | message_bubble, chat_thread_screen |
| `askNewLocation`, `parseAskNewQuery` | `core/router/ask_route.dart` | THE way to start a prefilled / source-pinned Ask: `/ask/new?q=...&sources=calendar,contacts,files` (Today's "Prep me for <event>") | Opening a past chat (`/chat/:id`) | `q` is prefilled, never auto-sent. Full-screen route: `push` it | app_router |
| `AskRetriever`, `buildSourcedPrompt`, `citedItemSources` | `data/connectors/ask_retrieval.dart`, `ask_sources.dart` | Per-source search + context-budget packing into the delimited `<sources>` block; the grounded user turn; `[n]` -> chips | A second prompt path for connector text (`buildSourcesBlock` is the only way in) | Budget = doc-chat `excerptBudgetChars`, capped at 6,000 chars | chat_controller |
| `BoolPref` providers (`hideInAppSwitcherProvider`, `widgetShowNextEventProvider`, `morningBriefEnabledProvider`, `downloadNotificationsProvider`), `morningBriefMinutesProvider` | `core/settings/bool_pref.dart` | One-line persisted switches over PrefsStore | Anything needing a schema | Morning brief providers are stored only; scheduler arrives in Wave 3 | privacy_screen, notifications_screen |
| `ScreenPrivacy` | `core/privacy/screen_privacy.dart` | Channel `app.dhruva/privacy` -> Android FLAG_SECURE / iOS cover view (hide content in app switcher) | — | Android: also blocks screenshots | main.dart |
| `MicButton` | `features/voice/widgets/mic_button.dart` | Hold-to-talk mic (pulsing) | Non-voice actions | Pulse uses `pulseMedium` | composer, handsfree_screen |
| `TtsButton` | `features/voice/widgets/tts_button.dart` | Read-aloud control | — | — | message_bubble |

### Connectors data layer (`app/lib/data/connectors`, `app/lib/core/di/connector_providers.dart`) — Wave 2A, no screens

The UI waves (2B Settings, 2C Ask, 3A Today, 3B Inbox) read these; they never build their own queries or talk to the OS.

| Component | Path | Use for | When NOT to use | Gotchas / adaptation notes | Used by |
|---|---|---|---|---|---|
| `Connector`, `ConnectorStatus`, `ConnectorState` | `data/connectors/connector.dart` | The one contract (`id`, `displayName`, `status`, `connect()`, `sync()`, `revoke()`, `openSystemSettings()`); status drives every card (Not connected / Connected / Needs attention / Permission denied; `unsupported` = hide, e.g. notifications on iOS) | A plugin system (none exists: one class per source) | `detail` is a user-ready sentence that names the fix; show it verbatim | settings (2B), today (3A), inbox (3B) |
| `connectorListProvider` | `core/di/connector_providers.dart` | Live list of supported connectors + status (re-reads OS grants when built) | Items/search (use the item providers) | `unsupported` connectors are already filtered out | settings, today "Set up" card |
| `ConnectorStore`, `ConnectorItem`, `NotificationGroup` | `data/connectors/connector_store.dart` | Read items (plain classes, never drift rows), ledger, accounts | Writing items from a feature (only connectors write) | `upsertItems` is idempotent on (source, externalId); body capped 8 KB; dates round-trip as whole seconds | all |
| `todaysEventsProvider`, `nextEventsProvider`, `notificationGroupsProvider`, `ledgerProvider` | `core/di/connector_providers.dart` | Today / Inbox / privacy ledger | — | Listen to them; Riverpod 3 pauses an unlistened provider, so `container.read(p.future)` can hang in tests | today, inbox, settings |
| `SearchIndex`, `connectorSearchProvider` | `data/connectors/search_index.dart` | Grounding for Ask: `search(query, sources:, kinds:)` over items | Doc-chat chunks of an attached file (still `data/docs/grounding.dart`) | Engine chosen once (FTS5 or capped BM25 fallback); query text is never SQL/FTS syntax | ask (2C) |
| `inboxAvailableProvider` | `core/router/inbox_availability.dart` | Gates the Inbox tab: true when notifications (Android) are connected | — | Gmail joins in 0.7b | app_shell |
| `FolderConnector.indexNow()` | `data/connectors/folder_connector.dart` | The Library "Index now" button; scheduled indexing is charging-only | Reading file contents from a feature | One grant, 2,000 files, 20 MB each, 6 sections of 8 KB per file | library (2D) |
| `NotificationQueue` | `data/connectors/notification_queue.dart` | Draining the listener's JSON-lines queue | Anything but the notifications connector | Corrupt lines skipped, 2 MB read cap, commit-after-store | notification connector |
| `SyncService`, `ConnectorHub` | `data/connectors/sync_service.dart`, `connector_hub.dart` | `syncOnOpen()` / `refresh()` (single flight); the hub is the composition root shared with the WorkManager job | Per-connector reads (call the connector) | Every connector sync writes its own ledger row | main (bootstrap), settings pull-to-refresh |

### Today, brief and onboarding v2 (`app/lib/features/today`, `app/lib/features/onboarding`, `app/lib/core/notifications`) — Wave 3A

| Component | Path | Use for | When NOT to use | Gotchas / adaptation notes | Used by |
|---|---|---|---|---|---|
| `BriefFact`, `needsYou`, `looksActionable`, `unreadGroups`, `daySummary`, `clock` | `features/today/state/brief_facts.dart` | Numbered facts, the "Needs you" rules, read-state filtering, the header summary, the phone's 12/24 h clock | Anything a model should decide | Pure. Facts carry UNTRUSTED text: only into `buildRewritePrompt`'s sources block | today, timeline |
| `composeBrief`, `DayBrief` | `features/today/state/brief_compose.dart` | THE brief: 3-5 sentences from fixed templates (first meeting + attendees, count/span, overlap, free stretch, tomorrow, people waiting, notifications by app, open to-dos), each built with the facts that back it so a tapped span opens the right source | A model-written summary | No model, instant, name from About me; sentences and facts are built together, never matched afterwards | today (`dayBriefProvider`) |
| `checkRewrite`, `ungrounded`, `RewriteCheck` | `features/today/state/brief_grounding.dart` | The strict check a model's rewording must pass: every sentence cites real facts, and every number/time/capitalised word appears in the facts it cites | Trusting `[n]` markers alone (they prove nothing) | One failing sentence rejects the whole rewrite; 12/24 h agnostic; allowlist is You/Today/weekdays/months/the user's name | brief controller |
| `parseBrief`, `BriefSpan`, `BriefSentence` | `features/today/state/brief_parser.dart` | Turns model text (or a cached rewrite) into cited spans; drops sentences with no valid `[n]` | Free-form model output you want shown as is | Used by `checkRewrite`, which also counts the drops | grounding, brief card |
| `WrittenBrief`, `BriefCacheStore`, `shownRewrite`, `isBriefFresh`, `briefStillAllowed` | `features/today/state/brief_cache.dart` | The CHECKED rewrite with the facts it was checked against; shown only while fresh (3 h, same day) and the facts are unchanged; erased on disconnect | Caching the rule-written brief (it is recomputed) or a rejected rewrite (never) | Cache version 2: version-1 text (unchecked) is never shown | brief controller, card |
| `buildRewritePrompt`, `markedSentence` | `features/today/state/brief_prompt.dart` | The ONLY way the draft enters the rewrite prompt (escaped, delimited sources block) | — | NO sample sentence with names or times: small models copy examples verbatim | brief controller |
| `BriefWriter` / `EngineBriefWriter` | `features/today/state/brief_writer.dart` | Seam over the on-device model for the brief; shares the engine lease with chat | Chat turns (use ChatController) | Loads the most recently used model if none is loaded; tests inject a fake | brief controller |
| `briefControllerProvider` | `features/today/state/brief_controller.dart` | The optional "Rewrite in my words": on a tap only, foreground only; accepted only if `checkRewrite` passes, else the rule-written brief stays and "Kept the checked version" shows | Background work (never); writing on open (never) | A failed or rejected try never leaves an ungrounded brief; a result for facts that changed meanwhile is discarded | today |
| `todayClockProvider`, `upNextEventsProvider`, `contactsDirectoryProvider`, `dayBriefProvider`, `briefFactsProvider`, `unreadNotificationGroupsProvider`, `openTodoCountProvider`, `notificationsReadAtProvider` | `features/today/state/today_data.dart` | Today's reads over the Wave 2A providers; `unreadNotificationGroupsProvider` is the one notifications view (brief, Needs you, summary) so "Mark all read" means the same everywhere | Settings / Inbox screens (use `connector_providers.dart`) | The clock is a provider so tests pin "now" | today, timeline |
| `AttendeeLine` | `features/today/ui/today_widgets.dart` | Names on one line, cut at name boundaries ("Sana +2") | Free text | The first name always shows | up next |
| `RouteTransitionGuard` | `core/widgets/route_transition_guard.dart` | Ignore taps while this screen's own route is still animating in (the finger still on the button that opened it) | Anything not a route destination | Does nothing without a route animation | today |
| `whenText`, `itemWhenText`, `shortDate`, `shortTime` | `data/connectors/local_time.dart` | "Mon 2 Nov, 11:00–12:00" in LOCAL time for sources blocks, chips and sheets | UTC ISO strings in prompts (the model answers in UTC) | Re-exported by `ask_sources.dart` | sources block, source chips |
| `buildTimeline` | `features/today/state/day_timeline.dart` | Slots events and notification groups on the "See day" rail with a now marker | — | Events win ties; yesterday's notifications are ignored | timeline |
| `TodayCard`, `SectionHeader`, `PersonAvatar`, `AvatarStack`, `SkeletonBar`, `InfoPill` | `features/today/ui/today_widgets.dart` | Today's card surface, headers, avatars (contact photo or initial), static skeletons | Other features (copy the idea, ADR-002) | Skeletons are static on purpose (no looping animation) | today, timeline, sheets |
| `CitedText` | `features/today/ui/brief_card.dart` | Text with tappable cited phrases and a press state | Plain text | Keeps one recognizer per span across rebuilds; a replaced recognizer would swallow the tap | brief card |
| `EventSheet`, `NotificationGroupSheet` | `features/today/ui/today_sheets.dart` | Read-only detail sheets (Prep / Open in calendar / Draft reply) | Editing events | Everything shown is untrusted text; it is only displayed | today, timeline |
| `connectAndSync` | `core/di/connector_actions.dart` | One tap: OS permission, then read | Revoke / settings pages (call the connector) | Returns the status; the card shows the fix | today, onboarding |
| `ConnectStep` | `features/onboarding/ui/connect_step.dart` | Onboarding "Start with your day" (Allow / Not now, extras, download strip) | — | Gmail row intentionally absent until 0.7b | onboarding |
| `MorningBriefScheduler`, `NotificationGateway`, `nextBriefTimes` | `core/notifications/morning_brief.dart` | The daily "Your brief is ready to read" notification; constant text only | Any notification carrying user data (never) | Schedules the next 7 mornings as one-shot inexact alarms on each launch (no tz database) | settings, main |

### Connectors UI, Library, Inbox (Wave 3B)

| Component | Path | Use for | When NOT to use | Gotchas / adaptation notes | Used by |
|---|---|---|---|---|---|
| `ConnectorsScreen`, `ConnectorSheet`, `confirmDisconnect`, `FolderSection`, `ExcludedAppsSheet` | `features/settings/ui/connectors_screen.dart`, `features/settings/widgets/connector_sheet.dart` | Settings > Connectors: one row per available connector (state, what it reads, one button), a connector that needs the user gets its own card with the reason + fix; tap a connected row for its sheet (folder index, apps to skip, Disconnect) | Anything outside Settings | Gmail is deliberately not listed until 0.7b. Disconnect always confirms with `ConnectorCopy.disconnectEffect`; "Open system settings" is offered only when the OS holds the permission (`hasOsPermission`) | router `/settings/connectors` |
| `ConnectorCopy` / `copyFor`, `statusLine`, `needsFix`, `ledgerTitle`, `ledgerWhen`, `clockText` | `features/settings/state/connector_copy.dart` | The words and icons of every connector: reads, disconnect consequence, button labels, status line, ledger sentences | Hard-coding a connector sentence in a widget | Pure; `connector_copy_test` pins the copy | settings screens |
| `LedgerSection`, `LedgerFactBanner`, `LedgerRow`, `LedgerScreen` | `features/settings/widgets/ledger_widgets.dart`, `features/settings/ui/ledger_screen.dart` | The privacy ledger: header fact, latest entries, See all (`/settings/connectors/ledger`), Clear ledger | | Counts only, never content; clearing never touches data or connectors | connectors screen |
| `ConnectorActions` / `connectorActionsProvider` | `core/di/connector_actions.dart` | Every user-tapped connector action: connect (+ first read), disconnect (+ optional OS settings), Index now / cancel, choose folder, apps to skip | Direct `hub.byId(..)` calls from a widget | All actions go through the hub, so the background job follows (`syncBackgroundJob`); `openSystemSettings` is best-effort (never throws) | settings, library, inbox, today, onboarding |
| `connectorResumeProvider`, `ConnectorHub.onResume()` | `core/di/connector_providers.dart`, `data/connectors/connector_hub.dart` | Refresh every connector when the app returns to the foreground; read right away from a source that just became usable; keep the background job in step | | Watched by `DhruvaApp` | main.dart |
| `connectorAccountsProvider`, `folderFilesProvider`, `inboxNotificationsProvider`, `externalOpenerProvider` | `core/di/connector_providers.dart` | Account config (folder total, skipped apps), one entry per indexed folder file, the last week of notifications, hand-off to the OS viewer / source app | | `ExternalOpener` is the test seam for `folder.open` / `apps.launch` | library, inbox |
| `FolderIndexStatus` | `data/connectors/folder_index_status.dart` | "312 of 340 files ready to search" + "Finishes while charging" wording and progress fraction | | Files that cannot be read (too large, scanned) count as done, not "waiting" | library, connectors sheet |
| `LibraryScreen`, `FolderBlock`, `DocumentsSection`, `TodosSection`, `SavedSection`, `FileSheet`, `SavedSheet`, `FileSearchScreen` | `features/library/**` | Library: folder block, documents (chat attachments + folder files), to-dos with check-off, saved replies, file search with Open file / Ask about this file | | Every section has a real empty state with a working next step | router `/library`, `/library/search`, `/library/documents`, `/library/saved` |
| `LibraryStore`, `parseTodos` | `data/library/library_store.dart`, `data/library/todo_parser.dart` | Saved replies and to-dos (schema v8); conservative parser for the "Extract to-dos" reply | | Plain bullets only count when the whole reply is a list; the add button is always a tap | chat thread, library |
| `ChatRouteArgs.sourceItemIds`, `ChatThreadState.sourceTitles` | `features/chat/state/chat_controller.dart` | "Ask about this file / notification": `/chat/new?source=<item id>` (repeatable) pins connector items as the chat's sources; their text goes through `buildSourcesBlock` only | Putting item text in the user's message | Session-only; the stored message is what the user typed | library, inbox |
| `MessageBubble.onSave`, `todoCount` / `onAddTodos` | `features/chat/widgets/message_bubble.dart` | Save to Library; "Add N to your to-dos" under an Extract to-dos reply | | Check mark replaces the icon after the tap (no new glyphs) | chat thread |
| `InboxScreen`, `InboxRowTile`, `InboxItemScreen`, `groupInbox`, `appFilters` | `features/inbox/**` | Notifications Today / Earlier, per-app chips, row -> detail (Ask about this, Open app, Mark read) | | Rows ask for summaries only while built (`cacheExtent: 0`); read mark survives re-ingest | router `/inbox`, `/inbox/item/:id` |
| `InboxSummarizer` | `features/inbox/state/inbox_summarizer.dart` | Lazy one-line summaries: visible rows only, foreground only, one at a time, engine idle, cached in `items.summary`; pauses while a row/chat is open | Bulk or background summarising | Releases a model it loaded itself; never competes with chat (`EngineLease`) | inbox |

## Layout & shell patterns

- Not yet catalogued. Candidates for a later pass: screen scaffolds in `features/*/ui/*_screen.dart` (AppBar + body + composer), bottom-sheet wrapper pattern used by model_picker_sheet, report_sheet, emoji_picker_sheet.

## Tokens & hooks

| Token/Hook | Path | Rule |
|---|---|---|
| Colors (dark + light role sets) | `app/lib/core/theme/design_tokens.dart` (`darkTokenColors`, `lightTokenColors`) | Mirror of `design-tokens.json` (repo root). Edit the JSON first; `test/core/theme/app_theme_test.dart` enforces equality. |
| Typography roles | `app/lib/core/theme/design_tokens.dart` (`tokenDisplayLarge` … `tokenLabelSmall`) | Fraunces for display/headline/title-large; Manrope for UI; Noto Devanagari fallbacks. |
| Spacing | `TokenSpacing` / `DhruvaTokens.spacing` | 4, 8, 12, 16, 20, 24, 32, 40, 48, 64, 80. Use the scale, not literals. |
| Radius | `TokenRadius` / `DhruvaTokens.radius` | 0, 4, 8, 12, 16, 24, full (9999). |
| Elevation | `tokenElevation` / `DhruvaTokens.elevation` | Levels 0–5; dark uses surfaceTint opacity, light uses midnight-tinted shadows. |
| Motion durations | `TokenMotionDuration` / `DhruvaTokens.motion` | instant 100, fast 150, base 200, moderate 300, slow 450, slower 600, pulseMedium 900, pulseSlow 1400. |
| Motion curves | `TokenMotionCurve` / `DhruvaTokens.motion` | standard, decelerate, accelerate, emphasized, linear. No bounce/elastic/spring. |
| Theme access | `Theme.of(context).extension<DhruvaTokens>()!` | Only lookup for non-ColorScheme/TextTheme tokens. |
| ThemeData build | `app/lib/core/theme/app_theme.dart` | Builds ThemeData from tokens. |

## House conventions

- Use `DhruvaTokens` (`extension<DhruvaTokens>()`) for spacing, radius, motion. Do not hardcode numbers.
- Use `Theme.of(context).colorScheme` for colors; `DhruvaTokens.success/warning` for the non-M3 pair.
- Motion: "settles, not bounces." No elastic/spring curves.
- Brand loading state is `DhruvaLoader`; brand mark is `DhruvaStar`.

## Legacy / do-NOT-copy

| Component | Path | Why not | Use instead |
|---|---|---|---|
| Hardcoded `Colors.transparent` in widgets | `features/models_hub/widgets/curated_tab.dart`, `features/voice/ui/handsfree_screen.dart`, `features/vision/widgets/image_lightbox.dart` | Local overrides bypass theme | Theme/ColorScheme-based values, or a documented token |
| Inline `Duration(milliseconds: N)` | `core/update/shorebird_update_banner.dart:28` (200ms), `features/chat/ui/chat_search_screen.dart:54` (250ms), `features/chat/widgets/message_bubble.dart:271` (900ms) | Off-scale | `TokenMotion` values (base=200, pulseMedium=900). 250ms has no token; decide whether to add one or use `moderate` (300). |

## Extraction candidates

| Pattern | Copies at | Blocking? |
|---|---|---|
| Hardcoded `EdgeInsets.*(<number>)` | 34 occurrences outside tokens; heaviest in `features/models_hub/ui/model_detail_screen.dart` (8), `features/models_hub/ui/downloads_screen.dart` (6), `features/models_hub/ui/models_hub_screen.dart` (5), `features/models_hub/widgets/download_progress_tile.dart` (3), `features/chat/ui/model_picker_sheet.dart` (3) | No, but drifts from spacing scale |
| `Colors.transparent` overrides | 4 occurrences (see Legacy) | No |
| Hardcoded font sizes | 2 occurrences (`features/characters/widgets/emoji_picker_sheet.dart:93` fontSize 26; `import_preview_dialog.dart` comment references 24) | No |
| Inline `Duration(milliseconds: N)` | 8 occurrences outside tokens (see Legacy) | No |
| Hardcoded `BorderRadius.circular(N)` / `Radius.circular(N)` | 0 found in grep (check `BorderRadius.circular` with a non-literal form before relying on this) | — |
| Material `Color(0x...)` literals | 0 outside `design_tokens.dart` (66 inside it, all expected) | No |
| Shared empty/error states duplicated in features | `ErrorStateView` / `EmptyStateView` are canonical; verify no feature re-implements them | Check during redesign |
| Permission / "access is off" cards: `_ConnectCard` (`today/ui/brief_card.dart`), the digest attention card (`today/ui/notification_sections.dart`), `_AccessBanner` (`inbox/ui/inbox_screen.dart`), `_AttentionCard` (`settings/ui/connectors_screen.dart`) | 4 different comps, each with its own title/body/one button. They share an action (`connectorActionsProvider.openSystemSettings`, consolidated in Wave 4) but not a layout (different surfaces, different card chrome in the locked comps) | No. Merge into one `AccessCard` only if the comps are re-cut |
| Status pills: `InfoPill` (`today/ui/today_widgets.dart`, coloured) and `_Pill` (`today/ui/quick_actions.dart`, icon + label on surface) | Different roles (state vs. action chip), not drift | No |
| `ageLabel` (`today/state/day_text.dart`: "5 min ago" for the brief footer) vs `timeAgo` ("5m ago") | Two spellings on purpose (a sentence vs. a list-row suffix); keep unless copy is unified | No |

Hardcoded-value counts are regex-based (`grep -rnE`), not AST-based. Treat as a floor.

## Gotchas, workarounds & learnings (append-only, dated)

- `2026-11-01` (Wave 1) — Shell branches are `/today`, `/inbox`, `/ask`, `/library`; everything else is full-screen. Old tab routes (`/chat`, `/characters`, `/models`, `/playground`, `/workflows`) are redirects (`legacyRouteRedirect`). Never `push` a shell-branch route from outside the shell (blank-page bug); `test/core/router/shell_routes_test.dart` sweeps `lib/` for it.
- `2026-11-01` — `zsh` does not word-split unquoted variables in `for x in $var` loops. Use `bash -c` for consumer-count shell loops → rerun in bash (source: registry seed pass).
- `2026-11-01` — `design_tokens.dart` is a hand-transcribed mirror of `design-tokens.json`. Drift is caught by `test/core/theme/app_theme_test.dart`, not by the compiler (source: registry seed pass).
- `2026-11-01` (Wave 2A) — `device_calendar_plus` 0.8.x refuses any calendar read unless `WRITE_CALENDAR` is declared and granted (its Android `PermissionService` requires both), and 0.9+ needs Flutter 3.44. Android therefore reads the calendar through our own `dhruva_connectors` plugin with `READ_CALENDAR` only; the package is used on iOS only. `test/platform/connectors_platform_test.dart` fails if any WRITE permission appears.
- `2026-11-01` (Wave 2A) — The shared doc-chat tokenizer split on combining marks, which shattered Devanagari words ("पार्टी") into 1-character tokens that were then dropped. `\p{M}` now stays inside a word (`data/docs/bm25.dart`); covered by `search_index_test.dart`.
- `2026-11-01` (Wave 2A) — Drift stores `DateTime` as whole unix seconds and returns local time: compare instants as seconds, never with `==` (a UTC draft never equals the stored local value).
- `2026-11-01` (Wave 3B) — Widget tests that watch drift streams (Library, Inbox) fail the pending-timer check on teardown unless the DB closes streams synchronously: use `streamSafeTestDb()` (`test/support/app_harness.dart`), not `AppDatabase(NativeDatabase.memory())`. Under the widget-test clock dart:io file IO and `Stream.first` on drift never complete: seed items with `seedFolder(...)` and read with `db.select(..).get()`.
- `2026-11-01` (Wave 3B) — Drift tables cannot have a column named `text` (clashes with `Table.text()`); the to-do column is `task`. Schema is now v8 (saved_answers, todos). If another wave also bumps the schema, renumber at merge and regenerate `database.g.dart`.
- `2026-11-01` (Wave 3B) — `Inbox "Open app"` needs launcher visibility on Android 11+: the app manifest declares a MAIN/LAUNCHER `<queries>` intent (not QUERY_ALL_PACKAGES, which `connectors_platform_test` bans). `folder.open` resolves its URI through the same `confinedDocumentUri` check as `folder.fetch`.
- `2026-11-01` (Wave 2A) — Native connector code is a plugin (`app/third_party/dhruva_connectors`), not `MainActivity`: the WorkManager background engine registers plugins but never runs MainActivity, so a MainActivity channel is invisible to the background job.
- `2026-11-02` (Wave 3A) — Dart: a tap recognizer replaced during a rebuild (the press highlight calls `setState` on pointer-down) never fires `onTap`. `CitedText` keeps one recognizer per span for its whole life.
- `2026-11-02` (Wave 3A) — `flutter_local_notifications` needs `isCoreLibraryDesugaringEnabled` + `desugar_jdk_libs` in the app's Gradle file and its two receivers in the manifest (the plugin does not merge them). Without the time-zone database the scheduler uses UTC instants computed from the local clock, re-issued each launch.
- `2026-11-02` (Wave 3A) — Widget tests for screens with a periodic ticker (`minuteTickProvider`) must not `pumpAndSettle` for the timer's sake; `settle()` in `test/features/today/today_harness.dart` pumps a fixed number of frames instead.

- `2026-11-01` (Wave 3C) — Ask citations share the `Messages.sourcesJson` column with document-page citations: item entries carry `"k":"item"`, document entries keep their original shape, each decoder skips the other's entries. A reply grounded in both stores both.
- `2026-11-01` (Wave 3C) — Ask's Auto never grounds a turn in a source the user has not connected (it would answer "not in your calendar" for an empty calendar). The gate is the `connector_accounts` row (local DB only, no OS call), so it is safe inside the controller and in tests.
- `2026-11-02` (Today round 4) — Small on-device models fabricate in the brief (they copied the prompt's sample sentence and invented names; a valid `[n]` marker opened an unrelated source). The default brief is now rule-written (`composeBrief`); "Rewrite in my words" is optional and accepted only through `checkRewrite`. Never put a sample sentence with names or times in a prompt, and never trust a citation marker as evidence.
- `2026-11-02` (Today round 4) — A `SnackBar` with an action persists until dismissed (Flutter default): pass `persist: false` and a `duration` for courtesy notices ("Model ready").
- `2026-11-02` (Today round 4) — Prep / Plan my day / Ask my files use the ONE Ask mechanism, `askNewLocation(q:, sources:, focus:)`; the parallel `pinnedSources` / `focusEventId` args are gone.

## One mechanism per concept (Wave 4)

If you need one of these, use the mechanism in the right-hand column. A second way to do it is a bug.

| Concept | The one mechanism | Where | Never |
|---|---|---|---|
| Start Ask grounded in sources / prefilled / event-focused | `askNewLocation(q:, sources:, focus:)` -> `/ask/new` | `core/router/ask_route.dart` | Extra route args, `pinnedSources` / `focusEventId`-style side channels |
| OS permission for a connector | `PermissionGate` (device sources) through `BaseConnector.connect()`; copy words the retry / blocked / revoked cases once | `data/connectors/system_sources.dart`, `base_connector.dart`, per-connector `_retry` / `_blocked` / `_off` | A screen calling the OS permission API, or wording a denial itself |
| User-tapped connector actions (connect, disconnect, index, skip apps, **open OS settings**) | `connectorActionsProvider` | `core/di/connector_actions.dart` | `hub.byId(..).openSystemSettings()` from a widget (Wave 4 removed four copies; `openSystemSettings` is best-effort, never throws) |
| Which notifications count as read (Today digest, brief facts, Needs you, day summary, See day) | `unreadNotificationGroupsProvider` (from `notificationsReadAtProvider`) | `features/today/state/today_data.dart` | Reading `notificationGroupsProvider` directly on a Today surface |
| Is the calendar off (revoked after connecting) | `calendarOffProvider`, applied inside `todayEventsProvider` / `upNextEventsProvider` | `features/today/state/today_data.dart` | Counting events straight from the store |
| Which installed model a text feature writes with | `StorageManager.listTextModels()` (voice models excluded), then the loaded engine if there is one | `data/downloads/storage_manager.dart` | Filtering `sherpa-voice/` at the call site |
| Download progress text | `downloadFraction` / `downloadFinishing` | `core/di/model_download.dart` | Computing a percent from bytes in a widget |
| Row timestamp / age label | `shortWhen`, `timeAgo` | `core/format/when.dart` | A private `_relativeTime` |
| Brief rewrite acceptance | `checkRewrite(raw, facts, draft:)` (numbers, times, names, AND lowercase content words) | `features/today/state/brief_grounding.dart` | Showing model text that did not pass it |
| Verification codes in notifications | `looksLikeVerificationCode(title, text, pkg:)` before anything is stored | `data/connectors/otp_guard.dart` | Redacting at display time |
| Privacy ledger rows | `ConnectorStore.recordSync` (one row per read with its own count; never "Read 0") | `data/connectors/connector_store.dart` | `addLedger(read, 0)` |
| Product name / wordmark | `AppIdentity` | `core/identity/app_identity.dart` | A string literal of the name |
| Platform chrome (Rule 6) | `ChromeScaffold` / `AdaptiveAppBar` / `AdaptiveTabBar` | `core/widgets/platform_chrome.dart` | A hand-rolled blur bar |
| Untrusted text into a model | The delimited `<sources>` block (`buildSourcesBlock`) | `data/connectors/sources_block.dart` | Interpolating item text into an instruction |

- `2026-11-02` (Wave 4) — The brief's rewrite check used to inspect only numbers, times and CAPITALISED words, so "Standup ... is cancelled", "was moved to the boardroom" and "You should skip it" passed: a claim hides in a lowercase verb. `checkRewrite` now also rejects any lowercase content word that is in neither the cited facts nor the rule-written sentence it rewrites; only grammar, connectives and a short list of schedule verbs (`_freeWords`) are free. Add to that list deliberately, never modals ("should", "must", "need") or state changes.
- `2026-11-02` (Wave 4) — Inbox summaries were dropped for the session whenever a try was cut short (opening a row, backgrounding) or failed, and the summariser could pick a `sherpa-voice/` model or evict a model another feature had loaded. Rows now stay wanted until written or given up on (3 tries, 10 s apart), voice models are excluded (`listTextModels`), and a model that is already loaded is used as it is.
- `2026-11-02` (Wave 4) — The doc-chat "Reading…" chip has a Cancel (`ChatController.cancelDocumentRead`): the chip clears at once and a late result is dropped by a generation counter. The extraction isolate cannot be killed from the provider, but it ends on its own (20 s limit, RSS watchdog whose limit scales with device RAM through `extractionRssLimitFor`).
