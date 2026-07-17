/// Per-repo download/install state for the search-results LISTING (Phase B,
/// D1-D3). The GGUF analog of `voice_models_controller.dart`: subscribes to
/// the same broadcast `DownloadManager.progress`, but keyed by repoId (a
/// search row is one `HfModelSummary`) instead of a fixed catalog entry.
///
/// The listing row's trailing affordance is a single state machine driven by
/// this map: Download → (resolving → progress ring, cancellable) → Installed
/// (Chat + Delete). Because search results carry no quant/size/url (only the
/// per-repo endpoint does — see `model_detail_provider.dart`), [download]
/// lazily fetches the repo's files on tap, picks a default quant
/// ([pickDefaultQuant]), and enqueues — no detour through the detail screen.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/di/providers.dart';
import '../../../core/failures/app_failure.dart';
import '../../../data/downloads/download_manager.dart';
import '../../../data/hf_api/default_quant.dart';
import 'storage_controller.dart';

enum ListingModelStatus {
  notInstalled,

  /// Fetching the repo's file list + license to resolve a default quant —
  /// the indeterminate window before the download task exists.
  resolving,
  downloading,
  installed,
  failed,
}

final class ListingModelState {
  final ListingModelStatus status;

  /// 0..1 while [status] is `downloading`; meaningless otherwise.
  final double progress;
  final String? errorMessage;

  /// The active download's taskId while downloading — so the row's cancel
  /// affordance can reach `DownloadManager.cancel`.
  final String? taskId;

  /// Drift row id of the installed model, used by [delete]. Set once
  /// `status == installed`.
  final int? installedId;

  const ListingModelState({
    this.status = ListingModelStatus.notInstalled,
    this.progress = 0,
    this.errorMessage,
    this.taskId,
    this.installedId,
  });
}

final listingDownloadControllerProvider =
    AsyncNotifierProvider<
      ListingDownloadController,
      Map<String, ListingModelState>
    >(ListingDownloadController.new);

class ListingDownloadController
    extends AsyncNotifier<Map<String, ListingModelState>> {
  StreamSubscription<DownloadProgress>? _sub;

  @override
  Future<Map<String, ListingModelState>> build() async {
    final manager = await ref.watch(downloadManagerProvider.future);
    ref.onDispose(() => unawaited(_sub?.cancel()));
    _sub = manager.progress.listen(_onProgress);
    return _loadInstalled();
  }

  /// Seeds the map from what's already on disk so a repo downloaded earlier
  /// (here, or via the detail screen's quant picker) shows as installed on
  /// its search row. Keyed by repoId — the same id a search row carries.
  Future<Map<String, ListingModelState>> _loadInstalled() async {
    final installed = await ref
        .read(storageManagerProvider)
        .listInstalledModels();
    return {
      for (final m in installed)
        m.repoId: ListingModelState(
          status: ListingModelStatus.installed,
          installedId: m.id,
        ),
    };
  }

  /// D1: enqueue the default quant for [repoId] straight from the listing.
  /// Fetches license (gated repos can't be downloaded without HF sign-in —
  /// same rule the detail screen enforces) then the file list, picks a
  /// default quant, and enqueues.
  Future<void> download(String repoId) async {
    _set(repoId, const ListingModelState(status: ListingModelStatus.resolving));
    try {
      final client = ref.read(hfApiClientProvider);
      final license = await client.getModelLicenseInfo(repoId);
      if (license.requiresAuth) {
        _set(
          repoId,
          const ListingModelState(
            status: ListingModelStatus.failed,
            errorMessage:
                'Gated on Hugging Face — requires sign-in, not supported yet.',
          ),
        );
        return;
      }
      final files = await client.getRepoFiles(repoId);
      final quant = pickDefaultQuant(client.quantVariantsFrom(files));
      if (quant == null) {
        _set(
          repoId,
          const ListingModelState(
            status: ListingModelStatus.failed,
            errorMessage: 'No downloadable GGUF quant in this repo.',
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
      await manager.enqueue(request, freeBytes: freeBytes);
      _set(
        repoId,
        ListingModelState(
          status: ListingModelStatus.downloading,
          taskId: request.taskId,
        ),
      );
    } on AppFailure catch (e) {
      _set(
        repoId,
        ListingModelState(
          status: ListingModelStatus.failed,
          errorMessage: e.message,
        ),
      );
    }
  }

  /// Cancels an in-flight download and reverts the row to not-installed.
  Future<void> cancel(String repoId) async {
    final taskId = state.value?[repoId]?.taskId;
    if (taskId == null) return;
    final manager = await ref.read(downloadManagerProvider.future);
    await manager.cancel(taskId);
    _set(repoId, const ListingModelState());
  }

  /// D3: delete an installed model from the listing row, reusing
  /// `StorageManager.delete`. Refreshes the Installed-tab provider too.
  Future<void> delete(String repoId) async {
    final id = state.value?[repoId]?.installedId;
    if (id == null) return;
    try {
      await ref.read(storageManagerProvider).delete(id);
      _set(repoId, const ListingModelState());
      ref.invalidate(storageControllerProvider);
    } on AppFailure catch (e) {
      _set(
        repoId,
        ListingModelState(
          status: ListingModelStatus.installed,
          installedId: id,
          errorMessage: e.message,
        ),
      );
    }
  }

  void _onProgress(DownloadProgress prog) {
    final repoId = prog.repoId;
    // Voice bundles ride the same stream but have their own tab — ignore.
    if (repoId.startsWith('sherpa-voice/')) return;
    switch (prog.state) {
      case DownloadState.complete:
        unawaited(_markInstalled(repoId));
      case DownloadState.failed:
        _set(
          repoId,
          ListingModelState(
            status: ListingModelStatus.failed,
            errorMessage: prog.errorMessage ?? 'download failed',
          ),
        );
      case DownloadState.canceled:
        _set(repoId, const ListingModelState());
      case DownloadState.queued:
      case DownloadState.running:
      case DownloadState.paused:
      case DownloadState.verifying:
        final total = prog.totalBytes ?? 0;
        final progress = total > 0
            ? (prog.downloadedBytes / total).clamp(0.0, 1.0)
            : 0.0;
        _set(
          repoId,
          ListingModelState(
            status: ListingModelStatus.downloading,
            progress: progress,
            taskId: prog.taskId,
          ),
        );
    }
  }

  Future<void> _markInstalled(String repoId) async {
    // Resolve the fresh drift row id so Delete has something to act on.
    final installed = await ref
        .read(storageManagerProvider)
        .listInstalledModels();
    final match = installed.where((m) => m.repoId == repoId).toList();
    _set(
      repoId,
      ListingModelState(
        status: ListingModelStatus.installed,
        installedId: match.isEmpty ? null : match.first.id,
      ),
    );
  }

  void _set(String repoId, ListingModelState next) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData({...current, repoId: next});
  }
}
