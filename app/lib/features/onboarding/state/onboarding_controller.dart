/// First-run onboarding state (PRD v0.3 WS2): the "shown once" flag store,
/// the device-RAM read the recommended pick classifies against, and the
/// single-model download controller that drives the guided "pick → download →
/// ready" step.
///
/// Onboarding can't import `features/models_hub` (ADR-002 bans cross-feature
/// imports), so it drives the download straight through the `data/` pipeline
/// (`HfApiClient` + `DownloadManager` + `StorageManager`) rather than reusing
/// `ListingDownloadController`. It stays deliberately simpler than the listing
/// controller: ONE model at a time, text-only (the recommended pick is always
/// a chat model — `recommendedStarterModel` excludes vision — so there's no
/// mmproj-projector chaining to coordinate here).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/device_info/device_info_service.dart';
import '../../../core/device_info/model_tier.dart';
import '../../../core/di/providers.dart';
import '../../../core/failures/app_failure.dart';
import '../../../data/downloads/download_manager.dart';
import '../../../data/hf_api/default_quant.dart';

/// Persists whether the user has finished OR skipped onboarding. A single
/// boolean, so a sentinel file (present == complete) rather than a Drift
/// table + schema migration on the shipped v4 schema, or a new
/// shared_preferences dependency — the laziest durable store that needs no
/// codegen, no migration, and no network.
abstract interface class OnboardingStore {
  Future<bool> isComplete();
  Future<void> markComplete();
}

final class FileOnboardingStore implements OnboardingStore {
  FileOnboardingStore(this.directory);

  /// The app's private support dir (same volume the models live under).
  final Directory directory;

  File get _flag => File(p.join(directory.path, '.onboarding_v1_complete'));

  // `existsSync`/`createSync` (not the async variants): the sentinel is a
  // single tiny stat on the app's own support dir, and `avoid_slow_async_io`
  // rightly flags the async `dart:io` file methods as slower here. The
  // interface stays `Future` so a future store (Drift, keychain) can be async.
  @override
  Future<bool> isComplete() async => _flag.existsSync();

  @override
  Future<void> markComplete() async {
    if (!_flag.existsSync()) _flag.createSync(recursive: true);
  }
}

final onboardingStoreProvider = FutureProvider<OnboardingStore>((ref) async {
  final dir = await getApplicationSupportDirectory();
  return FileOnboardingStore(dir);
});

/// True once onboarding is done — read ONCE at startup (`main`) to choose the
/// initial route, so a fresh install lands in the guided flow and every later
/// launch goes straight to chat.
final onboardingCompleteProvider = FutureProvider<bool>((ref) async {
  final store = await ref.watch(onboardingStoreProvider.future);
  return store.isComplete();
});

/// Onboarding's own device-RAM read for the recommended-pick classification.
/// A 3-line re-read of the shared core service rather than importing
/// `models_hub`'s `deviceMemoryProvider` (ADR-002).
final onboardingMemoryProvider = FutureProvider<DeviceMemoryInfo>((ref) {
  return ref.watch(deviceInfoServiceProvider).getMemoryInfo();
});

enum OnboardingDownloadStatus {
  idle,
  resolving,

  /// The resolved default quant is bigger than this device's RAM tier
  /// comfortably runs. NOT a dead-end: the download step offers a "download
  /// anyway" confirm that re-runs [download] with `force: true` — the same
  /// informed "may be slow" choice the hub's listing/detail screens give,
  /// so first-run isn't LESS safe than the hub (would otherwise download a
  /// too-big model fully and then OOM at chat-load).
  oversizeWarning,
  downloading,
  installed,
  failed,
}

final class OnboardingDownloadState {
  final OnboardingDownloadStatus status;

  /// The repo currently being downloaded/installed (null while [idle]).
  final String? repoId;

  /// 0..1 while [status] is `downloading`; meaningless otherwise.
  final double progress;
  final String? errorMessage;

  /// Drift row id of the installed model, set once `status == installed` —
  /// what the success step hands to chat so the first conversation opens with
  /// this model already loaded.
  final int? installedId;

  const OnboardingDownloadState({
    this.status = OnboardingDownloadStatus.idle,
    this.repoId,
    this.progress = 0,
    this.errorMessage,
    this.installedId,
  });
}

final onboardingDownloadControllerProvider =
    AsyncNotifierProvider<
      OnboardingDownloadController,
      OnboardingDownloadState
    >(OnboardingDownloadController.new);

class OnboardingDownloadController
    extends AsyncNotifier<OnboardingDownloadState> {
  StreamSubscription<DownloadProgress>? _sub;
  String? _activeRepoId;

  /// The in-flight download's task id — held so [cancel] can stop it (the
  /// download step's Cancel affordance / Android back). Deterministic
  /// (`repoId::fileName`), set at enqueue time.
  String? _activeTaskId;

  @override
  Future<OnboardingDownloadState> build() async {
    final manager = await ref.watch(downloadManagerProvider.future);
    ref.onDispose(() => unawaited(_sub?.cancel()));
    _sub = manager.progress.listen(_onProgress);
    return const OnboardingDownloadState();
  }

  /// Resolve [repoId]'s default quant and enqueue it — the one-tap path,
  /// text-only (no mmproj chaining; the recommended pick is never a vision
  /// model). Mirrors the resolve step in `ListingDownloadController.download`
  /// against the same `data/` pipeline.
  ///
  /// [force] skips the RAM-tier guard — the "download anyway" path the
  /// `oversizeWarning` step offers. On a sub-4GB device even the smallest
  /// starter model (`recommendedStarterModel`'s last-resort fallback)
  /// classifies `notRecommended`, so without this guard first-run would
  /// silently download a model too big for the device and OOM at chat-load.
  Future<void> download(String repoId, {bool force = false}) async {
    _activeRepoId = repoId;
    state = AsyncData(
      OnboardingDownloadState(
        status: OnboardingDownloadStatus.resolving,
        repoId: repoId,
      ),
    );
    try {
      final client = ref.read(hfApiClientProvider);
      final license = await client.getModelLicenseInfo(repoId);
      if (license.requiresAuth) {
        _fail(repoId, 'This model needs a Hugging Face sign-in — try another.');
        return;
      }
      final files = await client.getRepoFiles(repoId);
      final quant = pickDefaultQuant(client.quantVariantsFrom(files));
      if (quant == null) {
        _fail(repoId, 'This model has no phone-ready download — try another.');
        return;
      }
      // Real per-device RAM-tier guard — the same one the hub's listing
      // controller applies. This is the first point the actual footprint is
      // known (the repo's file tree is fetched); `DownloadManager.enqueue`
      // only guards DISK space, so without this a too-big GGUF would download
      // fully and then OOM at chat-load. Refuse it up front unless forced.
      final footprintBytes =
          quant.file.sizeBytes + (quant.mmprojFile?.sizeBytes ?? 0);
      final memory = await ref.read(deviceInfoServiceProvider).getMemoryInfo();
      final tier = classifyModelTier(
        fileSizeBytes: footprintBytes,
        totalRamBytes: memory.totalBytes,
      );
      if (tier == ModelTier.notRecommended && !force) {
        // Cancelled during the resolve awaits above? Honour it over the warning.
        if (_activeRepoId != repoId) return;
        final neededGb = (ramFloorBytesFor(footprintBytes) / (1 << 30)).round();
        state = AsyncData(
          OnboardingDownloadState(
            status: OnboardingDownloadStatus.oversizeWarning,
            repoId: repoId,
            errorMessage:
                'This model may run slowly on this phone — models this size '
                'run best with about $neededGb GB of RAM. Download anyway?',
          ),
        );
        return;
      }
      final request = DownloadRequest(
        repoId: repoId,
        fileName: p.basename(quant.file.path),
        url: client.resolveDownloadUrl(repoId, quant.file.path),
        expectedSizeBytes: quant.file.sizeBytes,
        expectedSha256: quant.file.sha256,
        quant: quant.label,
        license: license.license,
        gated: license.requiresAuth,
      );
      final freeBytes =
          (await ref.read(deviceInfoServiceProvider).getStorageInfo())
              .freeBytes;
      final manager = await ref.read(downloadManagerProvider.future);
      // Cancelled during the resolve (HF/storage awaits above)? Bail before
      // starting a real background download the user believes they stopped —
      // `cancel()` nulls `_activeRepoId`, so this comparison catches it.
      if (_activeRepoId != repoId) return;
      await manager.enqueue(request, freeBytes: freeBytes);
      // Cancelled mid-enqueue: the task is now started but `cancel()` couldn't
      // reach its id yet (we hadn't set `_activeTaskId`) — stop it here so it
      // doesn't download fully as an orphan.
      if (_activeRepoId != repoId) {
        await manager.cancel(request.taskId);
        return;
      }
      _activeTaskId = request.taskId;
      state = AsyncData(
        OnboardingDownloadState(
          status: OnboardingDownloadStatus.downloading,
          repoId: repoId,
        ),
      );
    } on AppFailure catch (e) {
      _fail(repoId, e.message);
    }
  }

  /// Cancels the in-flight download and resets to idle — the download step's
  /// Cancel affordance (and Android back), so a large model on a slow link is
  /// never a dead-end. No-op if nothing is downloading. The manager's own
  /// `DownloadState.canceled` event will also arrive and land on the same
  /// idle state via [_onProgress].
  Future<void> cancel() async {
    final taskId = _activeTaskId;
    _activeRepoId = null;
    _activeTaskId = null;
    if (taskId != null) {
      final manager = await ref.read(downloadManagerProvider.future);
      await manager.cancel(taskId);
    }
    state = const AsyncData(OnboardingDownloadState());
  }

  void _onProgress(DownloadProgress prog) {
    if (prog.repoId != _activeRepoId) return;
    switch (prog.state) {
      case DownloadState.complete:
        unawaited(_markInstalled(prog.repoId));
      case DownloadState.failed:
        _fail(prog.repoId, prog.errorMessage ?? 'Download failed — try again.');
      case DownloadState.canceled:
        _activeRepoId = null;
        state = const AsyncData(OnboardingDownloadState());
      case DownloadState.queued:
      case DownloadState.running:
      case DownloadState.paused:
      case DownloadState.verifying:
        final total = prog.totalBytes ?? 0;
        final progress = total > 0
            ? (prog.downloadedBytes / total).clamp(0.0, 1.0)
            : 0.0;
        state = AsyncData(
          OnboardingDownloadState(
            status: OnboardingDownloadStatus.downloading,
            repoId: prog.repoId,
            progress: progress,
          ),
        );
    }
  }

  Future<void> _markInstalled(String repoId) async {
    final installed = await ref
        .read(storageManagerProvider)
        .listInstalledModels();
    final match = installed.where((m) => m.repoId == repoId).toList();
    state = AsyncData(
      OnboardingDownloadState(
        status: OnboardingDownloadStatus.installed,
        repoId: repoId,
        installedId: match.isEmpty ? null : match.first.id,
      ),
    );
  }

  void _fail(String repoId, String message) {
    state = AsyncData(
      OnboardingDownloadState(
        status: OnboardingDownloadStatus.failed,
        repoId: repoId,
        errorMessage: message,
      ),
    );
  }
}
