# Chat experience — design spec (Loop 4)

Design contract for `features/chat`. Every value below names the exact
token/role it comes from — `design-tokens.json` (canonical, ADR-003) via
`lib/core/theme/app_theme.dart` (Material roles + `TextTheme`) and
`lib/core/theme/dhruva_theme_extension.dart` (`DhruvaTokens`: spacing,
radius, elevation, motion, success/warning). Data-layer types referenced
below (`ConversationSummary`, `MessageInfo`, `SamplingParams`,
`InstalledModelInfo`, `EngineFailure` family) are the real T2/T3 types in
`lib/data/chat/`, `lib/data/downloads/storage_manager.dart`, and
`lib/engine_bindings/engine_service.dart` as of this loop — build against
them directly, don't invent parallel names.

No color, radius, spacing, or duration in this spec is a raw literal.
Anywhere a builder is tempted to hardcode a hex/px/ms, the intended token is
named explicitly; if it isn't, that's a spec bug — flag it, don't invent one.

---

## 1. Screen layout

Route: `/chat/:conversationId` (new conversation = no id, repository creates
on first sent message — never a row for an empty draft). `Scaffold` with:

```
┌─────────────────────────────────────────────┐
│ AppBar: ‹back  [Model chip ▾]      tok/s  ⋮ │  ← appBarTheme (Loop 4 theme:
├─────────────────────────────────────────────┤     transparent surfaceTint,
│                                               │     background-colored)
│           message list (reversed,            │
│           newest at bottom, auto-scroll)     │
│                                               │
│  ⭐ Runs 100% on your device                 │  ← trust mark, see 1.3
├─────────────────────────────────────────────┤
│  [composer: multiline input] [send/stop]     │  ← see 1.2
└─────────────────────────────────────────────┘
```

### 1.1 Model chip + tok/s ticker (AppBar)

- Left of center: a tappable chip — `ActionChip`-shaped, `radius.full`,
  background `colorScheme.surfaceContainerHighest` (i.e. the `surfaceVariant`
  token), text `textTheme.labelLarge` on `colorScheme.onSurfaceVariant`.
  Content: model's short label (last path segment of `InstalledModelInfo
  .repoId`, e.g. `Llama-3.2-1B-Instruct` from
  `bartowski/Llama-3.2-1B-Instruct-GGUF`) + a small chevron-down
  (Phosphor `CaretDown`, regular weight, 14px). Tap opens the model picker
  (bottom sheet, §6.3).
- Right side, only visible while `EngineEvent` stream is active for the
  current message (i.e. mid-generation): a live tok/s readout,
  `textTheme.labelMedium` on `colorScheme.onSurfaceVariant`, tabular-figure
  rendering (`FontFeature.tabularFigures()` so digits don't jitter the
  layout every update). Computed as specified in §3.2, not from
  `EngineCompletion.elapsedMs` (that number only exists at the end).
  Fades out (`motion.fast` / `motion.standard`) 300ms after the stream's
  `EngineCompletion` event, replaced by nothing (AppBar right side goes
  empty between turns — no stale "3.2 tok/s" sitting there looking live).
- No model installed: chip reads "Pick a model" in `colorScheme.error` text
  on `colorScheme.errorContainer` background, tap routes to `/models`
  (models hub) directly — see empty state §7.1, this is the same CTA
  surfaced in miniature.

### 1.2 Composer

- Bottom-pinned, `colorScheme.surface` background (elevated 1dp,
  `DhruvaTokens.elevation[1]`: `darkSurfaceTintOpacity 0.05` in dark,
  `lightShadow` list in light — both come for free from the theme's
  `cardTheme`-style surface treatment, don't hand-roll a shadow).
  Padding `spacing.md` (12) horizontal, `spacing.sm` (8) vertical, safe-area
  aware.
- A multiline `TextField` (no visible border — `filled: false` override on
  the input decoration theme for this one field; the composer's own surface
  IS the field's visual boundary), min 1 line / grows to max 6 lines then
  scrolls internally, placeholder `textTheme.bodyLarge` on
  `colorScheme.onSurfaceVariant`: "Message Dhruva…".
- Trailing circular button, `radius.full`, 40×40, `colorScheme.primary`
  background / `colorScheme.onPrimary` icon:
  - Idle + text present → send icon (`PaperPlaneTilt`, bold weight — the one
    place bold Phosphor weight is allowed outside an active/selected state,
    because this is the primary CTA of the whole screen).
  - Idle + empty text → same button, disabled state (`colorScheme.primary`
    at reduced opacity per Flutter's default `ButtonStyle` disabled
    treatment — no custom disabled color).
  - Generating → button swaps to a stop-square icon on
    `colorScheme.errorContainer` background, tap calls the same cancel path
    `debug_chat` already proved (`EngineService.cancel()`, <500ms per the
    Loop-2 HANDOFF). Crossfade between the two button states over
    `motion.fast` (150ms) / `motion.standard` easing — not an instant swap,
    not a bounce.
- System-prompt editor entry point: a small icon button (`SlidersHorizontal`,
  regular) left of the text field, opens the sampling settings sheet (§5)
  which contains the system-prompt field as its first section (§5.1) — one
  entry point for both, not two competing affordances fighting for the same
  32px of composer real estate.

### 1.3 Trust mark

A single quiet line above the composer, `textTheme.labelSmall` on
`colorScheme.onSurfaceVariant`, centered: the 4-point star glyph (12px, the
brand's recurring accent motif per `design-tokens.json` `iconography.motif`
— not a generic icon) + "Runs 100% on your device". Static, no animation, no
dismiss action — it's a permanent fact about the product, not a banner.
Present on every chat screen state (empty, populated, streaming, error)
except it's replaced by the empty-state's larger version when the message
list is empty (§7.2 reuses the same copy at `textTheme.bodyMedium` scale as
part of the empty-state composition, not stacked twice on screen).

---

## 2. Message bubbles

### 2.1 Shape and placement

| | User | Assistant | System |
|---|---|---|---|
| Alignment | right | left | center |
| Max width | 84% of message-list width | 84% | 100% (banner, not a bubble) |
| Background | `colorScheme.primaryContainer` | `colorScheme.surfaceContainerHighest` (surfaceVariant) | `colorScheme.surfaceContainerHighest`, 60% opacity |
| Text color | `colorScheme.onPrimaryContainer` | `colorScheme.onSurfaceVariant` | `colorScheme.onSurfaceVariant`, italic |
| Corner radius | `radius.lg` (16) all corners except bottom-right `radius.xs` (4) | `radius.lg` all corners except bottom-left `radius.xs` | `radius.sm` (8) all corners |
| Padding | `spacing.md` (12) all sides | `spacing.md` | `spacing.sm` (8) vertical, `spacing.md` horizontal |
| Vertical gap to next bubble (same role, no role change) | `spacing.xs` (4) | `spacing.xs` | — |
| Vertical gap to next bubble (role changed) | `spacing.md` (12) | `spacing.md` | `spacing.md` |

The asymmetric corner (`radius.xs` on the side pointing at the message's own
edge) is the only "tail" — no literal speech-bubble tail shape, consistent
with the tokens' house ban on decoration without semantic meaning. System
messages (e.g. "Model changed to Llama-3.2-1B") are rare, centered,
unobtrusive banners, not conversational turns — never right/left aligned.

### 2.2 Text content — markdown → TextTheme mapping

Assistant and user bubble content renders through a markdown pass (existing
package choice is flutter-core's call in T4; this spec fixes only the
*style* mapping, not the package). Every markdown element maps to a named
`TextTheme` role — no ad-hoc `TextStyle` literals in the renderer:

| Markdown | TextTheme role | Notes |
|---|---|---|
| Paragraph | `bodyLarge` | Base bubble text. |
| `# H1` / `## H2` / `### H3+` | `titleMedium` / `titleSmall` / `titleSmall` | Headings inside a chat bubble are rare and should never outrank the screen's own AppBar hierarchy — capped at `titleMedium`, never `headlineSmall`+. |
| **bold** | `bodyLarge.copyWith(fontWeight: FontWeight.w700)` | Manrope has no separate bold TextTheme role; weight-bump the base style. |
| *italic* | `bodyLarge.copyWith(fontStyle: FontStyle.italic)` | |
| `inline code` | `bodyMedium.copyWith(fontFamily: 'monospace')` on `colorScheme.surfaceContainerHighest` chip background, `radius.xs`, `spacing.xs` horizontal padding | See §2.3 for the monospace family. |
| Block quote | `bodyLarge` italic, left border `spacing.xs` (4) wide in `colorScheme.outline`, `spacing.sm` left padding | |
| Bullet/numbered list | `bodyLarge`, `spacing.sm` indent per level | |
| Link | `bodyLarge` in `colorScheme.secondary`, underline | Secondary = "small stars you steer by" per brand-proposal.md — exactly the wayfinding role a link is. |
| Table | `bodySmall` in cells, `outlineVariant` gridlines | Rare in chat; keep it dense, not a redesign of the bubble. |

### 2.3 Code blocks

- Full-width within the bubble (breaks out of the 84% max-width visually via
  negative margin back to the bubble edge — code needs the room, prose
  doesn't).
- Background `colorScheme.surface` (one step darker/lighter than the bubble
  background it sits inside, giving a visible "well" without a new hue),
  `radius.sm`, `spacing.sm` padding.
- Font: monospace system fallback (`Menlo`/`Roboto Mono`/platform default —
  no bundled monospace font this loop, out of scope; declaring one is a
  Loop-4-follow-up if code density in practice demands it), size matches
  `bodyMedium.fontSize` (14), `height: 1.429` (same multiplier as
  `bodyMedium` — code shouldn't be visually denser than prose just because
  it's a different family).
- Language label top-left in `labelSmall` on `colorScheme.onSurfaceVariant`
  when the fence declares one (` ```dart `), omitted when it doesn't.
- Copy button top-right: icon-only (`Copy`, regular, 16px),
  `colorScheme.onSurfaceVariant`, no visible button chrome until hovered/
  focused (desktop) — always tappable on touch. On tap: copies raw code
  (not the rendered markdown) to clipboard, icon swaps to a checkmark
  (`Check`, `colorScheme.success`) for `motion.moderate` (300ms) then
  reverts. No snackbar — the icon swap IS the confirmation, don't stack a
  second one.

### 2.4 Message metadata row

Below each assistant bubble (not user — the user already knows what they
typed and when): a thin row in `labelSmall` on `colorScheme.onSurfaceVariant`
— relative timestamp ("2m ago"), and when `MessageInfo.tokCount` +
`MessageInfo.genMs` are both non-null, `"· 34 tok/s"` computed as
`tokCount / (genMs / 1000)`, one decimal. When `MessageInfo.status ==
MessageStatus.error`, this row is replaced by the error treatment (§8), not
appended to it. Regenerate and edit affordances live here too: two icon
buttons (`ArrowClockwise` regenerate, `PencilSimple` edit — user messages
only), 16px, `colorScheme.onSurfaceVariant`, revealed on tap-and-hold or
persistent-but-low-contrast (flutter-core's call which, given no hover
concept on mobile — always visible at reduced opacity is the safer default
for a touch-first app). Regenerate creates a new `MessageInfo` row with the
same `parentMessageId`, not an in-place mutation — matches the schema's
lineage design already in `chat_repository.dart`.

---

## 3. Streaming presentation

### 3.1 Partial token rendering

The assistant bubble appears the instant the first `EngineToken` arrives —
not before (no empty bubble placeholder waiting for text; that reads as a
layout glitch, not a typing indicator — see §3.3 for what fills the gap
before the first token). Bubble grows downward as text streams; the message
list's scroll position pins to bottom (`ScrollController.jumpTo` to
`maxScrollExtent`) on every growth **unless** the user has manually scrolled
up more than one viewport height, in which case streaming continues
off-screen and a "↓ New message" pill appears bottom-center (`radius.full`,
`colorScheme.primary` background, `labelLarge` on `colorScheme.onPrimary`,
tap scrolls to bottom and resumes auto-pin). This is the one place the spec
prescribes behavior over pure visual — getting this wrong (fighting a user's
manual scroll) is the single most common chat-UI complaint in the
competitor research (`orchestra/research/competitors.md`).

### 3.2 Batched-update cadence (60fps target)

Do not call `setState`/rebuild the message widget on every `EngineToken` —
llama.cpp on a fast device can emit tokens faster than 16ms apart, and a
rebuild per token is exactly the per-token-jank pattern the Loop-4 exit gate
[G2] calls out. Target: **batch token deltas into a buffer and flush to the
widget tree on a fixed timer, ≤1 flush per `motion.instant` (100ms)**, or
on `EngineCompletion`, whichever comes first. This caps visible updates at
10/sec — well under the 60fps *frame* budget while staying fast enough that
streaming still reads as live, not chunky. Live tok/s (§1.1) is computed
from the same buffer: token arrival timestamps (captured on arrival,
independent of flush cadence) divide into a trailing 1-second window,
matching `EngineCompletion.elapsedMs`'s own doc comment that inter-arrival
timing is the consumer's job, not the engine's.

### 3.3 Typing indicator

Fills the gap between "user hit send" and "first `EngineToken` arrives"
(prompt prefill can take a visible moment on longer contexts). A small
inline indicator at the position the assistant bubble will appear: three
dots using the brand's 4-point star motif instead of generic circles (per
`iconography.avoid`: "generic circular spinners" are explicitly banned),
each star at 6px, opacity-pulsing in a staggered sequence,
`motion.moderate` (300ms) per pulse, `motion.emphasized` easing, looping.
Replaced by the real bubble the instant the first token arrives — no
crossfade needed, the indicator's removal and the bubble's appearance are
the same visual event.

---

## 4. Reasoning-token treatment (`<think>` blocks)

Maps to `MessageInfo.reasoningContent` (already split from `content` at the
repository layer — the UI never parses `<think>` tags out of raw text
itself).

- Rendered as a collapsible block **above** the main response content,
  inside the same assistant bubble (not a separate bubble — it's part of
  one turn).
- **Collapsed by default.** Header row: a small chevron-right (`CaretRight`,
  regular, rotates 90° to `CaretDown` on expand — actual rotation animation,
  `motion.fast` / `motion.standard`, not an icon swap) + label
  `"Reasoning…"` in `textTheme.labelMedium` on `colorScheme.onSurfaceVariant`
  *while still streaming*, changing to `"Reasoning (12s)"` (the wall-clock
  duration reasoning took) once that phase completes — a static duration
  reads as more trustworthy than a vague ellipsis once it's actually over.
- Tap anywhere on the header row toggles expand/collapse —
  `AnimatedSize`, `motion.moderate` (300ms), `motion.standard` easing, no
  bounce (tokens ban overshoot outright — this is exactly the kind of
  affordance an AI-generic UI would give a spring to, don't).
- Expanded content: `bodyMedium` (one step down from the main response's
  `bodyLarge` — reasoning is supporting material, not the answer),
  `colorScheme.onSurfaceVariant` (quieter than the main response's
  `onSurfaceContainer`-equivalent text), left border `spacing.xs` wide in
  `colorScheme.outlineVariant`, `spacing.sm` left padding — visually
  "indented" relative to the main answer, same visual language as a block
  quote (§2.2) since both are "this is here for context, not the point."
- While actively streaming reasoning tokens (before the model emits the
  closing think-tag and the repository sets a duration), auto-expand is
  **off** — collapsed-with-ellipsis is the resting state even mid-stream,
  so a verbose reasoning model doesn't turn the chat screen into a wall of
  scratch text by default. A user who taps to expand while it's still
  streaming sees it grow live, same batching rule as §3.2.

---

## 5. Sampling settings sheet

A modal bottom sheet (`bottomSheetTheme`: `colorScheme.surface`,
`surfaceTintColor: colorScheme.surfaceTint`, top corners `radius.xl` (24)
per the theme already wired in `app_theme.dart`). Opens from the composer's
sliders icon (§1.2). Entrance: slide up + fade, `motion.moderate` (300ms),
`motion.decelerate` easing (a sheet arriving should settle in, not
punch-fast — `decelerate`, not `standard`, matches the token set's own
philosophy note: "entrances settle rather than bounce").

### 5.1 System prompt (first section, always visible, not collapsed)

A multiline `TextField`, `bodyLarge`, placeholder "You are a helpful
assistant…", bound to `ConversationSummary.systemPrompt`. Persists on sheet
close (no explicit save button for this field — it's conversation-scoped
config, saves like any other field edit).

### 5.2 Sliders

One slider per `SamplingParams` field, in this order, each row:
label (`titleSmall`) + live value (`labelLarge`, tabular figures) on the
same line, slider below (`SliderThemeData` inherits `colorScheme.primary`
active track / `colorScheme.surfaceContainerHighest` inactive track — no
override needed, Material 3's default slider already reads the scheme).

| Field | Range | Step | Default (`SamplingParams()`) |
|---|---|---|---|
| Temperature | 0.0 – 2.0 | 0.05 | **0.8** |
| Top-P | 0.0 – 1.0 | 0.01 | **0.95** |
| Top-K | 0 – 200 (slider caps below the schema's 1000-max — values above 200 are a power-user edge case; expose via the raw-value tap-to-type affordance every slider row gets, not the drag range) | 1 | **40** |
| Max tokens | 1 – 4096 (slider cap; schema allows to 32768, same tap-to-type escape hatch) | 1 (drag), free entry (type) | **512** |
| Context length | 512 – 8192 (slider cap; schema allows to 131072) | 256 | **4096** |

Every row's value label is also a tap target that swaps to a plain number
`TextField` for exact entry — sliders are for feel, typing is for precision,
both routes write the same `SamplingParams` field. `SamplingParams.validate()`
(already implemented, throws `ValidationFailure`) runs on sheet-close commit
(not per-keystroke) — a slider literally cannot produce an invalid value
given the ranges above, but typed entry can (e.g. `maxTokens > contextLength`
after independent edits), so the commit-time check exists for exactly that
path. On validation failure: inline error text under the offending field in
`colorScheme.error`, sheet stays open, nothing is persisted until it's
valid.

### 5.3 Reset

A `TextButton` at the sheet's bottom, "Reset to defaults" —
`colorScheme.error` text (destructive-adjacent: it discards the user's
tuning, deserves the same visual weight as a delete action, even though
it's reversible by re-tuning). Resets every field to `SamplingParams()`'s
bare defaults (table above) in the sheet's local state; still requires the
sheet's normal close-to-commit — reset doesn't auto-save either, symmetry
with every other field.

---

## 6. Model picker, folders, search

### 6.1 Model chip → picker sheet

Tapping the AppBar model chip (§1.1) opens a bottom sheet listing installed
models from `storageManagerProvider` (`InstalledModelInfo`), same visual
language as §5's sheet shell. Each row: model label (`titleSmall`) +
quant/size subtitle (`bodySmall` on `onSurfaceVariant`, e.g. "Q4_K_M ·
770MB"), selected model gets a leading filled star-glyph indicator (brand
motif again, not a generic checkmark) instead of a checkbox. Selecting a
model calls the repository's `touchLastUsed` path (already named in the
Loop-4 BLACKBOARD plan) and updates `ConversationSummary.modelId` for the
current conversation — switching models mid-conversation is allowed (the
schema's `modelId` is per-conversation, not locked at creation).

### 6.2 Folders + search

Reachable from the conversation-list screen (the screen *before* an open
chat — this spec's §1–5 cover the open-chat screen; the list screen gets
its own lighter treatment here since it's mostly `ListTile` rows, not a
bespoke layout):

- Folders render as a horizontal chip row at the top (`ChipThemeData`
  already wired: `radius.full`), "All" chip first (unfiled + every folder),
  then one chip per `FolderInfo` ordered by `sortIndex`. Selected chip:
  `colorScheme.secondaryContainer` background / `onSecondaryContainer` text
  (secondary, not primary — this is a filter/navigation action, not the
  screen's primary CTA).
- Search: a persistent search field at the very top (`InputDecorationTheme`
  default styling, no card wrapper), debounced 300ms
  (`motion.moderate`-adjacent but this is a debounce not an animation —
  reuse the number, don't invent a new one), calls
  `ChatRepository.search`. Results render as `ConversationSearchHit` rows:
  title (`titleSmall`) + snippet (`bodyMedium` on `onSurfaceVariant`, the
  matched term bold-weighted inline within the snippet).

---

## 7. Empty states

### 7.1 No model installed

Full-bleed center column (matches the onboarding hero's restraint per
brand-proposal.md §d — this is the same "hold still" register): star glyph
96px in `colorScheme.primary`(no story-fade sequence here, this isn't the
onboarding screen — reads instantly), headline
`"No model installed yet"` (`headlineSmall`, Fraunces — myth register even
in a utility empty state, per the type rationale: the app doesn't drop into
generic-sans mode just because nothing has happened yet), body
`"Pick a model from Hugging Face to start chatting — fully offline once it's on your device."`
(`bodyLarge`, `onSurfaceVariant`), one `FilledButton` "Browse models" →
routes to `/models`. No composer visible on this state (nothing to type
into yet — showing a disabled composer under an empty state is worse than
omitting it).

### 7.2 No conversations (model IS installed)

Same column layout, warmer register per the brief's "warm first-run copy":
star glyph 72px, headline `"Start your first conversation"`
(`headlineSmall`), body `"Your chats stay on this device — no account, no cloud, no one watching."`
(`bodyLarge`, `onSurfaceVariant` — deliberately echoes the onboarding
screen's second line from brand-proposal.md §d verbatim; this is the
product's one repeated promise, repetition is the point, not
copy-fatigue), trust mark (§1.3) at `bodyMedium` scale directly under the
body line rather than pinned to the composer (there's no composer content
above it to separate from), one `FilledButton` "New chat".

---

## 8. Error states

Maps `EngineFailure` subtypes (`lib/engine_bindings/engine_service.dart`)
to a message + recovery affordance, per ADR-002's taxonomy rule ("UI maps
taxonomy → user message + recovery affordance"). Rendered as a compact
inline card at the position the failed assistant message would have
occupied (not a full-screen error, not a snackbar — the conversation stays
visible and scrollable around it), `colorScheme.errorContainer` background,
`onErrorContainer` text, `radius.md`, `spacing.md` padding, leading
`WarningCircle` icon (Phosphor, regular, `onErrorContainer`).

| `EngineFailure` | User message | Recovery affordance |
|---|---|---|
| `EngineOutOfMemoryFailure` | "This model needs more memory than your device has free right now." | Primary button "Try a smaller model" → model picker (§6.1) pre-filtered to `ModelTier.comfortable`/`possible` for this device (reuses `core/device_info`'s existing tiering, don't reinvent it here); secondary text button "Retry anyway". |
| `EngineLoadFailure` | "Couldn't load this model — the file may be corrupted or an unsupported format." | Primary button "Re-download" (routes to the model's detail screen, reuses Loop-3's existing download flow) — do NOT offer plain "Retry", a load failure at this layer rarely self-resolves. |
| `EngineDecodeFailure` | "Something went wrong generating a response." | Primary button "Retry" (re-runs the same request — this is the generic transient-failure case). |
| `EngineStateFailure` | Not user-facing as a bubble at all — this is a usage-error class ("generation already in flight"); the composer's send button should already be disabled/showing stop-state (§1.2) so this failure class shouldn't reach the UI. If it does anyway, treat as `EngineDecodeFailure`'s generic case, and file it — a UI-visible `EngineStateFailure` means a composer state bug upstream, not a real chat error. |
| `EngineDisposedFailure` | "The model was unloaded." | Primary button "Reload model" (re-triggers load with the conversation's current `modelId`). |
| `EngineValidationFailure` | Should never surface from real chat traffic — `checkGenerateArgs` rejects empty prompts before the engine is touched, and the composer's send button is disabled on empty input (§1.2), so this is defense-in-depth, not a reachable UI path. If it somehow renders, generic `EngineDecodeFailure` copy + "Retry" is the fallback. |
| `EngineUnknownFailure` | "Something unexpected happened." | Primary button "Retry"; secondary text button "Copy error details" (copies `EngineFailure.cause`/`message` for bug reports — the only error card that exposes raw internals, because there's no typed guidance to give instead). |

Every retry affordance re-sends by constructing a new `MessageInfo` with the
same `parentMessageId` as the failed attempt (same lineage mechanism as
regenerate, §2.4) — a failed message is never silently mutated in place.

---

## 9. Export

Entry point: overflow menu (`⋮` in the AppBar, §1 layout) → "Export
conversation" → a small action sheet with two rows, "Markdown" and "JSON"
(icons `FileMd`/`FileCode` regular, `labelLarge`). Both formats are already
implemented (`chat_export.dart`: `formatConversationMarkdown`,
`formatConversationJson`) — this spec fixes only the entry point and the
platform share action, not the format. Selecting a format calls the
system share sheet (`share_plus` or platform intent — flutter-core's
package call) with the formatted string as plain text/`.md`/`.json` file
content; no in-app preview screen this loop (YAGNI — the share sheet's own
preview, where the OS provides one, is enough).

---

## 10. Motion specification summary

Every duration/easing pair below is a direct `DhruvaTokens.motion.*` lookup
— no bespoke `Duration`/`Curve` literals anywhere in `features/chat`.

| Interaction | Duration | Easing |
|---|---|---|
| Assistant bubble first appearance (fade+slight rise, 8px) | `motion.fast` (150ms) | `motion.decelerate` |
| Send/stop button crossfade (§1.2) | `motion.fast` (150ms) | `motion.standard` |
| tok/s ticker fade-out (§1.1) | `motion.fast` (150ms) | `motion.standard` |
| Reasoning block expand/collapse (§4) | `motion.moderate` (300ms) | `motion.standard` |
| Reasoning chevron rotation (§4) | `motion.fast` (150ms) | `motion.standard` |
| Code-block copy icon → checkmark hold (§2.3) | `motion.moderate` (300ms) | n/a (hold, not eased) |
| Typing-indicator star pulse, per pulse (§3.3) | `motion.moderate` (300ms) | `motion.emphasized` |
| Sampling/model-picker sheet entrance (§5, §6.1) | `motion.moderate` (300ms) | `motion.decelerate` |
| Sampling/model-picker sheet exit | `motion.fast` (150ms) | `motion.accelerate` |
| "↓ New message" pill appear/disappear (§3.1) | `motion.fast` (150ms) | `motion.standard` |
| Token batch flush cadence (§3.2, not an animation but a budget) | ≤`motion.instant` (100ms) per flush | n/a |

**Documented deviation (designer nit 6, Loop-4 QA/design fix pass):** the
sheet entrance/exit row's *duration* is sourced from the tokens
(`showModalBottomSheet`'s `sheetAnimationStyle: AnimationStyle(duration:
reverseDuration:)`), but the *curve* column (`motion.decelerate`/
`motion.accelerate`) is NOT applied — verified against the Flutter SDK
source (`material/bottom_sheet.dart`): `AnimationStyle.curve`/
`.reverseCurve` are read by other widgets (`ExpansionTile`,
`PopupMenuButton`, …) but never consumed by `_ModalBottomSheetRoute`'s
transition builder, so there is no public hook to override the modal
bottom sheet's curve without reimplementing the route. The sheet still
uses Flutter's own internal transition curve, not a bounce/elastic one —
this is a "can't reach it," not a "didn't bother" gap. Forcing it would
mean vendoring `_ModalBottomSheetRoute`, a bigger maintenance surface than
this one curve column is worth; revisit if Flutter ever plumbs
`AnimationStyle.curve` through for modal bottom sheets.

No `Curves.bounceOut`/`elasticOut`/spring-physics anywhere in this feature —
matches `design-tokens.json` `motion.easing.banned` and is a permanent
regression guard in `app_theme_test.dart`'s "no bounce/elastic/spring
curves" check (that test only covers the theme extension's own curve
constants; a `features/chat` code-review should still eyeball for a
`SpringSimulation`/bounce curve sneaking in via a raw `AnimationController`).

---

## Open items for flutter-core (T4), not decisions the builder should make

None — every layout, color, radius, spacing, and motion value above
resolves to a named token or an existing data-layer type. Package choices
left explicitly open (markdown renderer, share sheet) are marked YAGNI/
"flutter-core's call" because they're implementation substitutability, not
design decisions.
