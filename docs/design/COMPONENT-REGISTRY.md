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

Hardcoded-value counts are regex-based (`grep -rnE`), not AST-based. Treat as a floor.

## Gotchas, workarounds & learnings (append-only, dated)

- `2026-11-01` (Wave 1) — Shell branches are `/today`, `/inbox`, `/ask`, `/library`; everything else is full-screen. Old tab routes (`/chat`, `/characters`, `/models`, `/playground`, `/workflows`) are redirects (`legacyRouteRedirect`). Never `push` a shell-branch route from outside the shell (blank-page bug); `test/core/router/shell_routes_test.dart` sweeps `lib/` for it.
- `2026-11-01` — `zsh` does not word-split unquoted variables in `for x in $var` loops. Use `bash -c` for consumer-count shell loops → rerun in bash (source: registry seed pass).
- `2026-11-01` — `design_tokens.dart` is a hand-transcribed mirror of `design-tokens.json`. Drift is caught by `test/core/theme/app_theme_test.dart`, not by the compiler (source: registry seed pass).
- `2026-11-01` (Wave 2A) — `device_calendar_plus` 0.8.x refuses any calendar read unless `WRITE_CALENDAR` is declared and granted (its Android `PermissionService` requires both), and 0.9+ needs Flutter 3.44. Android therefore reads the calendar through our own `dhruva_connectors` plugin with `READ_CALENDAR` only; the package is used on iOS only. `test/platform/connectors_platform_test.dart` fails if any WRITE permission appears.
- `2026-11-01` (Wave 2A) — The shared doc-chat tokenizer split on combining marks, which shattered Devanagari words ("पार्टी") into 1-character tokens that were then dropped. `\p{M}` now stays inside a word (`data/docs/bm25.dart`); covered by `search_index_test.dart`.
- `2026-11-01` (Wave 2A) — Drift stores `DateTime` as whole unix seconds and returns local time: compare instants as seconds, never with `==` (a UTC draft never equals the stored local value).
- `2026-11-01` (Wave 2A) — Native connector code is a plugin (`app/third_party/dhruva_connectors`), not `MainActivity`: the WorkManager background engine registers plugins but never runs MainActivity, so a MainActivity channel is invisible to the background job.
