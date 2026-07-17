# State & Usability Diagnosis — v0.1.0-alpha

Scope: READ-ONLY diagnosis of state-management bugs + usability gaps on
`loop/ux-hardening` off main. No code changed. Line refs are `app/lib/...`.

## Verdict on the state-management question (up top)

**Do NOT swap Riverpod. The library is not the problem.** The architecture is
idiomatic and correct: engine/voice/downloads on isolates, DI root in
`core/di/providers.dart`, `AsyncNotifier` list-controllers that
refresh-after-mutation, a well-reasoned `autoDispose` + `keepAlive` on the
streaming chat controller (`chat_controller.dart:188-198`). The "feels broken"
symptoms are all **one root-cause bug repeated**: mutations that happen in
feature A do not invalidate the read-only provider that feature B is showing.
Riverpod gives you `ref.invalidate` for exactly this; the code just doesn't
call it in ~4 places. This is a handful of one-line fixes, not a rewrite.
Swapping to Bloc/GetX/etc. would reintroduce every one of these same gaps at
10x the risk.

---

## (a) Concrete state bugs — ranked by "feels broken"

### BUG 1 — [CRITICAL, ROOT CAUSE] Download completes → new model invisible everywhere until app restart

The single biggest "feels broken / can't start a convo" driver. When a
download finishes, `DownloadManager._completeDownload` writes the row
(`download_manager.dart:393 upsertInstalledModel`) and emits
`DownloadState.complete` on its progress stream — but **nothing invalidates the
providers that read the installed-model list**. Those reads are one-shot
`FutureProvider`/`AsyncNotifier` with no `autoDispose`, so they cache the
pre-download (empty) list forever:

- `features/chat/state/installed_models_provider.dart:12` — chat model picker
  + the Chat-tab FAB `_startNewChat` (`conversation_list_screen.dart:53,75`).
- `features/characters/state/installed_models_provider.dart:14` — character
  form default-model picker (`character_form_screen.dart:367`).
- `features/models_hub/state/storage_controller.dart:32` — the Models →
  **Installed** tab (`models_hub_screen.dart:262`) AND the Downloads screen's
  "Installed / completed" section (`downloads_screen.dart:158`).

Confirmed: grep shows the ONLY `invalidate`/`refresh` calls on these providers
are manual retry/pull-to-refresh handlers (`models_hub_screen.dart:267,281`).
No completion path touches them.

**Most damning single-screen instance:** on the **Downloads screen**, when a
download completes, the Active section drops it (its stream-fed
`downloadsControllerProvider` updates and filters `complete` out —
`downloads_screen.dart:55-61`) but the "Installed" section below
(`storageControllerProvider`) does **not** refresh — so the finished model
vanishes from Active and never appears under Installed. "Where did my download
go?!" on one screen, no navigation involved.

**First-run consequence:** fresh install → Chat tab shows `NoModelInstalledView`
"Browse models" (good). User downloads a model, returns to Chat →
`installedModelsProvider` still cached-empty → app **still** says "No model
installed yet" and the FAB still routes to `/models`
(`conversation_list_screen.dart:54-56`). This is exactly the reported "not able
to start a convo." The empty-state design is fine; this stale cache defeats it.

**Fix (single point, root cause, ADR-002-safe).** `DownloadsController` is kept
alive app-wide (the always-mounted `AppShell` watches
`downloadsControllerProvider` for the nav badge — `app_shell.dart:35`), and its
stream subscription (`downloads_controller.dart:27`) sees every completion. But
`DownloadsController` lives in `features/models_hub` and must not import
`features/chat` or `features/characters` (ADR-002). So do the invalidation at
the **composition root that is already allowed to import feature code** —
`app_shell.dart` (its own doc comment claims this exact privilege). Add a
listener there:

```dart
// app_shell.dart build(), composition root — already imports feature code.
ref.listen(downloadsControllerProvider, (prev, next) {
  final justCompleted = next.value?.values.any(
        (p) => p.state == DownloadState.complete) ?? false;
  if (justCompleted) {
    ref.invalidate(chat_installed.installedModelsProvider);
    ref.invalidate(char_installed.installedModelsProvider);
    ref.invalidate(storageControllerProvider);
  }
});
```

(Guard against re-firing on unchanged state by diffing prev/next complete-set if
needed.) One listener fixes the chat picker, the character picker, the Installed
tab, the Downloads "Installed" section, and the first-run "start a convo" path
simultaneously. Alternative if the team prefers to keep app_shell thin: a common
`installedModelsRevision` int provider bumped on completion that all three
providers `ref.watch` — more plumbing, same effect.

### BUG 2 — [HIGH] Clear-all history leaves the Chat list fully populated

`settings_screen.dart:157` calls `chatRepositoryProvider.clearAllHistory()`
directly on the repo, then shows a snackbar that literally reads *"Chat history
cleared. Pull to refresh the Chat tab to see it."* (`settings_screen.dart:162`).
The devs **knew** the list wouldn't update and shipped an instruction instead of
a fix. `conversationListControllerProvider` is a non-autoDispose `AsyncNotifier`
kept alive by the indexed-stack Chat branch, so it shows every deleted
conversation until pull-to-refresh or restart. Classic "I deleted everything and
nothing happened."

**Fix:** after `clearAllHistory()`, `ref.invalidate(conversationListControllerProvider)`
(settings already imports chat's repo provider from `core/di`; the controller
provider is in `features/chat` — do it via app_router/shell composition root, or
expose a repo-level change signal). Delete the apologetic snackbar text.

### BUG 3 — [HIGH] New conversation doesn't appear in the Chat list

`chat_controller.sendMessage` lazily creates the conversation row
(`chat_controller.dart:479 createConversation`) but never notifies
`conversationListControllerProvider`. The list is kept alive in the indexed
stack, so on pop-back the brand-new chat is absent until pull-to-refresh /
restart. Reads as "my chat disappeared."

**Fix:** on first successful `createConversation` in `sendMessage` (and in
`_buildFromCharacter`, `chat_controller.dart:324`), invalidate/refresh the
conversation-list controller. Same composition-root routing as BUG 2 to respect
ADR-002 (chat controller may legitimately touch chat's own list controller — it's
same-feature, so this one can be a direct `ref.invalidate` with no ADR concern).

### BUG 4 — [MEDIUM] Character's default-model picker also stale after a download

Same root cause as BUG 1, second `installedModelsProvider`
(`characters/state/installed_models_provider.dart:14`). Covered by BUG 1's fix
(the app_shell listener invalidates this copy too). Note: character *gallery*
reactivity is FINE — `charactersControllerProvider` refreshes after every
create/update/delete/import (`characters_controller.dart:_guarded → refresh`,
gallery watches it at `characters_gallery_screen.dart:27`). A created character
DOES appear in the gallery immediately.

---

## (b) Usability gaps — ranked

### U1 — [HIGH] First-run has no signposting beyond the empty state, and that empty state is defeated by BUG 1
The path exists (`NoModelInstalledView` → "Browse models" → `/models`), but (a)
there is **no onboarding** — cold launch drops straight onto an empty Chat list,
and (b) BUG 1 means it stays saying "no model" even after the user downloads
one. Fix BUG 1 first; the empty-state CTA is actually well-designed once it
refreshes. Optional: a one-line "Models live in the Models tab" hint. Do not
build a heavy onboarding flow — the empty-state CTA is the right pattern.

### U2 — [MEDIUM] After tapping "Download" in model detail, the completion is silent
No toast/snackbar on completion and (BUG 1) no list updates. User is left
guessing whether it worked and where the model went. The app_shell listener from
BUG 1 is the natural place to also fire a "X installed — start a chat" snackbar.

### U3 — [LOW] Chat FAB silently routes to Models when no model installed
`_startNewChat` (`conversation_list_screen.dart:54`) pushes `/models` with no
explanation when the list is empty. A one-line snackbar ("Download a model
first") would remove the "why did my New-chat button take me here?" confusion.
Minor — the empty-state view already explains it in the no-conversations case.

### U4 — [LOW] Nav/labels are otherwise clear
4-tab `NavigationBar` (Chat/Characters/Models/Settings) with labels + tooltips,
live download badge (`app_shell.dart:57`), sensible icons. Actions are labeled.
No major discoverability holes beyond the above.

---

## (c) Is Riverpod usage actually broken? — refute, with evidence

**Refuted. Usage is sound; the bug class is missing-invalidation, not misuse.**
Evidence the usage is correct:
- Mutating controllers correctly refresh-after-write within their own feature:
  `conversation_list_controller.dart:133 _guarded → refresh`,
  `characters_controller.dart:150 _guarded → refresh`,
  `storage_controller.dart:60 delete → _load`.
- `chat_controller.dart:188-198,601-618` — textbook `autoDispose` +
  `ref.keepAlive()`/`KeepAliveLink` so a stream keeps running when you navigate
  away mid-generation and is reclaimed when idle. This is *advanced-correct*, not
  broken.
- Isolate offloading is real (`llama_engine_service.dart:194`,
  `sherpa_voice_service.dart:69`) — inference/voice never block the UI isolate.
- The one honest smell is **two identical `installedModelsProvider` files**
  (chat + characters) — but it's a *deliberate, documented* ADR-002
  duplication, not an accident (see both files' header comments). It's the
  reason BUG 1's fix must invalidate two symbols; acceptable.

The gaps are entirely "an action in feature A didn't invalidate feature B's
read." That's a 4-line-of-fixes problem, not a library problem.

---

## (d) Top perf wins (real, not speculative)

1. **[LOW-MED] `AppShell` rebuilds on every download progress tick.**
   `app_shell.dart:35` does `ref.watch(downloadsControllerProvider)` and reads
   the whole map, but only needs the `hasActiveDownload` bool. During a download
   the map updates many times/sec, rebuilding the entire shell each time. Fix:
   `ref.watch(downloadsControllerProvider.select((v) => v.value?.values.any(_isActive) ?? false))`.
   Cheap rebuild, but pure churn — trivial win.
2. **[LOW] Avatars decode at full resolution.** `Image.file` with no
   `cacheWidth` at `character_avatar.dart:43` and `chat_thread_screen.dart:590`.
   A user-supplied PNG card avatar decodes full-size for a ~40px circle. Add
   `cacheWidth`. Minor unless users import large PNGs.
3. **No other real issues.** Large/growing lists already use lazy builders with
   pagination (model search `models_hub_screen.dart:219`, conversation list
   `:188`, messages). Installed-model lists rendered via `Column`/`.map` are
   bounded-small (fine). No heavy work found on the UI isolate.

---

## Priority order for the fix loop
1. BUG 1 (one app_shell listener) — kills the biggest "feels broken", fixes
   picker + Installed tab + Downloads section + first-run in one shot. Also
   resolves BUG 4 and enables U2.
2. BUG 2 (clear-all invalidate) — visible, embarrassing, one line.
3. BUG 3 (new-convo invalidate) — one line, same-feature, no ADR friction.
4. U1/U2/U3 snackbars + optional first-run hint — cheap polish once BUG 1 lands.
5. Perf #1 `.select` — trivial.
