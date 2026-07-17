# Download UX diagnosis — shipped v0.1.0-alpha

Read-only investigation. No code touched. Root: `/tmp/dhruva-ux/app/lib`.

## 1. Where the download button actually is (confirmed: user is right)

- **Search listing** (`features/models_hub/widgets/model_list_tile.dart:8-61`) — `ModelListTile` is pure nav: `ListTile(onTap: onTap, trailing: Icon(Icons.chevron_right))`. No download affordance, no progress, nothing. `onTap` (wired in `models_hub_screen.dart:242-247`) just does `context.push('/models/repo/...')`.
- **Model detail screen** (`features/models_hub/ui/model_detail_screen.dart:112-207`, `_QuantTile`) — this is the *only* place a `FilledButton.icon` "Download" exists, one per quant file. Tap path is confirmed: **Search tab → tap row → detail screen → pick a quant → tap Download → separate Downloads screen (via app-bar icon) to see it happen.** That's 4 taps + 1 screen-hop before any progress is visible anywhere.
- **Voice tab is the outlier and already does it right** — `voice_model_tile.dart` + `voice_models_controller.dart` put a download icon directly on the list row and turn it into a `CircularProgressIndicator` while downloading (`_trailing()` switch, lines 76-82). This is the exact pattern the user is asking for, already built and working, just not applied to the GGUF search tab. Treat `voice_models_controller.dart` as the reference implementation for the fix below, not a research project.

## 2. "No feedback that it started" — traced to the actual bug

`_QuantTile.build()` (`model_detail_screen.dart:144-193`) watches `downloadActionsControllerProvider` and shows a tiny 14px spinner inside the button + "Starting…" label **only** while `DownloadActionsController.enqueue()` (`state/download_actions_controller.dart:36-50`) is in flight. That call is just `await manager.enqueue(...)` — an async call that hands a task to `background_downloader` and returns almost instantly (typically <100ms). So the "pending" flicker is real but disappears before most users register it, and then the button silently reverts to its normal "Download" label/icon — even though the file is now actively downloading in the background. There is no snackbar, no toast, nothing. The button gives zero feedback that download is now in progress; the user has no way to tell from the detail screen (or anywhere else except manually opening Downloads) that anything happened.

**Root cause:** `DownloadActionsState` only tracks the enqueue *call*, not the download *task*. It has no subscription to `DownloadManager.progress`. The button's post-enqueue state is decided by `downloadActionsControllerProvider`, a provider that structurally cannot represent "downloading 40%" — it only has `pendingTaskIds` (enqueue in flight) and `errors`. This is the wiring gap for asks (b) below too.

## 3. Progress feed: it exists, it's just not plumbed to list items

`DownloadManager.progress` (`data/downloads/download_manager.dart:156`) is a `Stream<DownloadProgress>.broadcast()` — any number of listeners can subscribe, it's not exclusive to one screen. Two consumers already exist:
- `downloads_controller.dart:27-31` — accumulates every taskId's latest state into a `Map<String, DownloadProgress>` for the Downloads screen.
- `voice_models_controller.dart:81` + `_onProgress` (139-175) — same stream, filtered to voice catalog entries, drives per-row `progress` (0..1) that `VoiceModelTile` renders as a `LinearProgressIndicator`/`CircularProgressIndicator`.

**Nothing subscribes to this stream from `model_search_controller.dart` or `model_list_tile.dart`.** The search tab has never wired to `DownloadManager.progress` at all — that's the entire gap for "progress on the listing." It is not a limitation of the stream (it's broadcast, multi-listener, taskId-keyed by `repoId::fileName` — see `DownloadRequest.taskId` at `download_core.dart` no, `download_manager.dart:89`); it's simply unwired for this screen. The fix is structurally identical to what `voice_models_controller.dart` already does, just against `HfModelSummary` search results instead of a fixed catalog (see the data-availability caveat in §3a).

### 3a. The real complication: search results don't carry file/quant info

`HfModelSummary` (`data/hf_api/models/hf_model_summary.dart`) — one row of a search result — only has `id, likes, downloads, tags, pipelineTag, license`. **No quant file list, no size, no URL, no sha256.** Those only exist in `ModelDetailData.quants` (`model_detail_provider.dart`), fetched via `client.getRepoFiles(repoId)` — a per-repo network call the search endpoint doesn't return inline. A `DownloadRequest` (`download_core.dart:59-128`, needed to call `DownloadManager.enqueue`) requires `url`, `expectedSizeBytes`, ideally `expectedSha256` — none of which the listing has today.

So "download button on the listing" is not just a widget move — it requires one of:
1. **Lazy per-row detail fetch on first render/tap** — call `getRepoFiles(repoId)` when the row's download button is tapped (or prefetched), pick a default quant (recommended tier via `classifyModelTier`, same logic `_QuantTile`/`RecommendedRail` already use), then enqueue. Adds a network round-trip before the ring can start filling, but keeps license/gated-status gating intact (`license.requiresAuth` must still block, per the existing rule that license is shown before any download affordance — `model_detail_screen.dart:55-56` comment).
2. **Prefetch quant list for visible rows** — heavier, N extra API calls per page of results, not justified by the ask.

(1) is the lazy, correct option — same shape as `VoiceModelsController.download()`, just resolving quant/url first instead of it being static catalog data.

## 4. "Seamless" — current tap path vs. ideal

**Current:** Search tab → tap row (nav) → Detail screen loads (license/gated fetch + repo files fetch) → pick quant → tap Download → button briefly spins → **reverts to idle-looking "Download" label** → user must manually tap the app-bar download icon → Downloads screen → finds the row → watches a `LinearProgressIndicator`. 4 taps, 2 screens, no feedback loop closing back to where the user started.

**Ideal (matches what Voice tab already does today):** Search tab → tap **download icon on the row itself** → icon transitions in place to a `CircularProgressIndicator` (ring fills 0→100% from `DownloadManager.progress`) → on complete, ring becomes a checkmark/"open"/"use" state, no navigation required at any point. Row tap (not on the icon) still opens detail for the license/quant-picker path — that's a legitimate secondary flow for users who want a specific non-default quant, not the primary path.

## 5. Delete — same gap, same fix shape

Delete only exists in `_InstalledTab`/`StorageController.delete()` (`models_hub_screen.dart:320-333`, `storage_controller.dart:60-67`) — a trash icon on the "Installed" tab, gated behind a confirm dialog. Search listing and detail screen have **no delete affordance at all**, even for a repo the user has already downloaded — re-visiting a downloaded model's search row or detail page gives no "delete" or even "installed" indicator (compare to Voice tab's `VoiceModelStatus.installed` → checkmark + delete icon in `voice_model_tile.dart:61-75`). The fix is: extend the per-row state machine from §3 to include an `installed` status (checked via `StorageManager`/`storageControllerProvider`, keyed by repoId+fileName) so the row's trailing icon is a single state machine: not-installed → downloading (ring) → installed (check + delete icon), exactly mirroring `VoiceModelTile._trailing()`.

## 6. OS notifications — NOT configured, confirmed by grep

```
grep -rn "configureNotification\|TaskNotification\|notification" lib/ -i   → 0 matches
```

`background_downloader_backend.dart:24-33` enqueues every `bg.DownloadTask` with `updates: bg.Updates.statusAndProgress` only — no `notification:` field, and `FileDownloader().configureNotification(...)` is never called anywhere in the app (checked `main.dart`, `core/di/providers.dart`, the whole `lib/` tree).

**AndroidManifest.xml** (`android/app/src/main/AndroidManifest.xml`) declares only `INTERNET`. **No `POST_NOTIFICATIONS`** — required on Android 13+ (API 33) for any notification to show; without it, even a fully-configured `TaskNotificationConfig` silently shows nothing on modern Android.

### Recommendation: use background_downloader's own notifications, not flutter_local_notifications

`background_downloader` (pubspec: `^9.5.6`) ships first-class notification support (`TaskNotificationConfig`, verified in `/Users/ansh/.pub-cache/hosted/pub.dev/background_downloader-9.5.6/lib/src/models.dart:474-575` and `file_downloader.dart:1001-1025`) — it already owns the task lifecycle, already runs on Android's `WorkManager`/iOS `URLSession` in the background, and already substitutes `{progress}`, `{networkSpeed}`, `{timeRemaining}`, `{filename}` tokens into notification text and drives an Android progress bar (`progressBar: true`). Adding `flutter_local_notifications` as a second dependency to hand-roll this would duplicate what the existing package already does correctly and would require manually wiring progress updates from `DownloadManager.progress` into local-notification `.show()` calls on every update — more code, another permission-handling path, another place to get wrong. Ladder says: already-installed dependency solves it — use it.

**Exact wiring (once, at startup — e.g. `core/di/providers.dart` near where `downloadManagerProvider` builds the backend, or `main.dart` before `runApp`):**

```dart
FileDownloader().configureNotification(
  running: const TaskNotification(
    '{filename}', 'Downloading… {progress} · {timeRemaining} left',
  ),
  complete: const TaskNotification('{filename}', 'Download complete'),
  error: const TaskNotification('{filename}', 'Download failed'),
  paused: const TaskNotification('{filename}', 'Paused'),
  progressBar: true,      // Android progress bar in the notification
  tapOpensFile: false,    // GGUF files aren't user-openable; leave false
);
```

This must run before any `enqueue()` — `configureNotification` sets a *global* default config (`taskOrGroup: null`), so it applies to every task including voice-model downloads, no per-`DownloadTask` changes needed in `background_downloader_backend.dart`. (There's also `configureNotificationForTask`/`configureNotificationForGroup` for per-task overrides — not needed here, one config for all GGUF/voice downloads is fine.)

**Permission, required alongside it:**
1. `android/app/src/main/AndroidManifest.xml`: add
   ```xml
   <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
   ```
2. Request it at runtime (Android 13+ only; no-op/auto-granted on older Android and non-notification-gated on iOS < certain versions) — call once, e.g. right after `configureNotification`, or lazily on first enqueue:
   ```dart
   final status = await FileDownloader().permissions.status(PermissionType.notifications);
   if (status != PermissionStatus.granted) {
     await FileDownloader().permissions.request(PermissionType.notifications);
   }
   ```
   The plugin checks permission status itself before showing anything (per `doc/permissions.md`), so a denied/skipped request just means silently no notification — not a crash — but the request should still happen so most users actually get one.

No `flutter_local_notifications` needed. No native Android/iOS code changes beyond the manifest permission line — `background_downloader`'s own Android plugin manifest (`NotificationReceiver`, pause/resume/cancel intent actions) is already merged in via the plugin, confirmed by reading its bundled `AndroidManifest.xml`.

## 7. macOS repro — what's desktop-only vs. not

- The download **flow itself** (enqueue → progress stream → integrity check → drift row) is fully reproducible on macOS — `background_downloader` supports macOS/Windows/Linux with "no setup required" beyond a network-client entitlement for a *sandboxed* release build. This app's `macos/Runner/DebugProfile.entitlements` has `com.apple.security.app-sandbox` set to `false` for debug builds specifically (comment: "macOS is a Loop-2 verification target, not a release target"), so **no entitlement change is needed to repro downloads in a debug run** — sandbox is off entirely.
- **OS notifications are mobile-only for this plugin.** `background_downloader`'s README describes notification support explicitly as "mobile notifications" and `TaskNotificationConfig`/`NotificationReceiver` are Android/iOS-specific; there is no desktop notification path in this package. So (d) above is unverifiable on macOS by design — it needs an Android (API 33+ emulator/device, to also exercise the POST_NOTIFICATIONS gap) or iOS run to confirm visually. Not a gap in the diagnosis, just a platform-scoping note for whoever implements/QAs it.
- The circular-progress-ring UI change (§3/§4) and the listing-download/delete wiring (§3a/§5) are all Flutter-side and fully verifiable on macOS.

## Fix plan, prioritized by user impact

1. **(Highest — closes "no feedback" + "not seamless" together) Per-row download state on the search listing**, modeled directly on `voice_models_controller.dart`: a new controller (or extend `model_search_controller.dart`) that subscribes to `DownloadManager.progress`, keyed by `taskId`, resolving `repoId → default quant` lazily (§3a option 1) on first download tap. `ModelListTile` gains a trailing icon that is a state machine: idle download icon → `CircularProgressIndicator` (ring, driven by `progress: downloadedBytes/totalBytes` exactly like `DownloadProgressTile`'s `fraction` calc at `download_progress_tile.dart:23-26`) → check/installed + delete icon. This single change is what the user is actually asking for in "download model is not proper — give download button on the listing itself" + "button become circular progress" + "seamless."
2. **OS notifications** (§6): `configureNotification()` call once at startup + `POST_NOTIFICATIONS` manifest permission + runtime request. Small, self-contained, no dependency on #1 — can ship independently and in parallel.
3. **Delete on the listing** (§5): once #1's per-row state machine exists, "installed" is just another state in the same switch — cheap to add right after #1, reusing `storageControllerProvider`/`StorageManager.delete` for the actual deletion.
4. Detail screen keeps its own Download buttons as the "pick a specific quant" path — no change needed there beyond wiring it to the same per-row/per-taskId progress state so it doesn't regress to today's "reverts to idle after enqueue" behavior described in §2 (i.e. `_QuantTile` should also render a ring instead of the 14px spinner, and keep showing it after enqueue completes — same underlying subscription, no separate design).
