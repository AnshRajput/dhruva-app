/// Per-file "enqueue a download" action state for the model detail screen
/// (T5 §3). Tracks which task ids are mid-enqueue and the last enqueue
/// failure per task id (free-space guard errors, backend rejection, ...)
/// so each file's Download button renders its own pending/error state
/// without one file's failure clobbering another's.
///
/// Loop-7 T2: also the vision-quant download pairing coordinator (see
/// [enqueueVisionQuant]) — a vision model's mmproj projector rides the SAME
/// `DownloadManager` the plain [enqueue] path uses, chained sequentially
/// after the model file completes rather than enqueued concurrently, so the
/// projector's completion always finds the model's `installed_models` row
/// already written (no race to patch a row that doesn't exist yet).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/di/providers.dart';
import '../../../core/failures/app_failure.dart';
import '../../../data/downloads/download_manager.dart';
import '../../../data/hf_api/models/hf_repo_file.dart';
import '../../../data/hf_api/models/model_license_info.dart';
import '../../../data/hf_api/models/quant_variant.dart';

final class DownloadActionsState {
  final Set<String> pendingTaskIds;
  final Map<String, AppFailure> errors;

  const DownloadActionsState({
    this.pendingTaskIds = const {},
    this.errors = const {},
  });

  bool isPending(String taskId) => pendingTaskIds.contains(taskId);
  AppFailure? errorFor(String taskId) => errors[taskId];
}

/// Everything [DownloadActionsController] needs to chain-enqueue a vision
/// quant's mmproj after its model file completes.
final class _ProjectorPairing {
  final String repoId;
  final String modelTaskId;
  final String modelFileName;
  final HfRepoFile mmproj;
  final ModelLicenseInfo license;

  const _ProjectorPairing({
    required this.repoId,
    required this.modelTaskId,
    required this.modelFileName,
    required this.mmproj,
    required this.license,
  });
}

final downloadActionsControllerProvider =
    NotifierProvider<DownloadActionsController, DownloadActionsState>(
      DownloadActionsController.new,
    );

class DownloadActionsController extends Notifier<DownloadActionsState> {
  StreamSubscription<DownloadProgress>? _pairingSub;

  /// Keyed by the MODEL file's taskId — populated by [enqueueVisionQuant],
  /// consumed once that model download reaches a terminal state.
  final Map<String, _ProjectorPairing> _pendingModel = {};

  /// Keyed by the PROJECTOR file's taskId — populated once the model
  /// completes and its projector is chain-enqueued.
  final Map<String, _ProjectorPairing> _pendingProjector = {};

  @override
  DownloadActionsState build() {
    ref.onDispose(() => unawaited(_pairingSub?.cancel()));
    // Fire-and-forget: `build()` must return synchronously, but the pairing
    // listener has nothing to observe until the async `downloadManagerProvider`
    // resolves — same pattern as `characterRepositoryProvider`'s seeding.
    unawaited(_attachPairingListener());
    return const DownloadActionsState();
  }

  Future<void> _attachPairingListener() async {
    final manager = await ref.read(downloadManagerProvider.future);
    _pairingSub = manager.progress.listen(_onPairingProgress);
  }

  Future<void> enqueue(DownloadRequest request) async {
    final pending = {...state.pendingTaskIds, request.taskId};
    final errors = {...state.errors}..remove(request.taskId);
    state = DownloadActionsState(pendingTaskIds: pending, errors: errors);
    try {
      final manager = await ref.read(downloadManagerProvider.future);
      final storageInfo = await ref
          .read(deviceInfoServiceProvider)
          .getStorageInfo();
      await manager.enqueue(request, freeBytes: storageInfo.freeBytes);
      _finish(request.taskId);
    } on AppFailure catch (e) {
      _finish(request.taskId, error: e);
    }
  }

  /// Enqueues a vision-capable [quant]'s model file, then (once it
  /// completes) its paired [QuantVariant.mmprojFile] — both through the same
  /// resumable [DownloadManager] `enqueue` does. Only meaningful when
  /// `quant.isVision`; callers should fall back to plain [enqueue] for a
  /// text-only quant (`quant.mmprojFile == null`).
  ///
  /// If the model download fails, nothing further happens — same as a plain
  /// [enqueue] failure. If the model succeeds but the projector download
  /// later fails (network drop, storage guard, ...), the model's
  /// `installed_models` row is left exactly as the model's own completion
  /// wrote it: `isVision: true, mmprojPath: null` — the "needs projector"
  /// half-state (see `database.dart`'s doc), not a silently-lost or
  /// double-written row. The failure is also surfaced here under the
  /// model's own taskId, same slot [errorFor] already exposes for a plain
  /// download failure, so the existing per-tile error UI picks it up
  /// without a separate "projector failed" affordance.
  Future<void> enqueueVisionQuant({
    required String repoId,
    required QuantVariant quant,
    required ModelLicenseInfo license,
  }) async {
    final mmproj = quant.mmprojFile;
    final modelFileName = p.basename(quant.file.path);
    final modelRequest = DownloadRequest(
      repoId: repoId,
      fileName: modelFileName,
      url: ref
          .read(hfApiClientProvider)
          .resolveDownloadUrl(repoId, quant.file.path),
      expectedSizeBytes: quant.file.sizeBytes,
      expectedSha256: quant.file.sha256,
      quant: quant.label,
      license: license.license,
      gated: license.requiresAuth,
      isVision: mmproj != null,
    );
    if (mmproj != null) {
      _pendingModel[modelRequest.taskId] = _ProjectorPairing(
        repoId: repoId,
        modelTaskId: modelRequest.taskId,
        modelFileName: modelFileName,
        mmproj: mmproj,
        license: license,
      );
    }
    await enqueue(modelRequest);
  }

  void _onPairingProgress(DownloadProgress progress) {
    final modelPairing = _pendingModel[progress.taskId];
    if (modelPairing != null) {
      switch (progress.state) {
        case DownloadState.complete:
          _pendingModel.remove(progress.taskId);
          unawaited(_enqueueProjector(modelPairing));
        case DownloadState.failed:
        case DownloadState.canceled:
          // The model itself never installed — nothing paired to clean up,
          // same as a plain download failure/cancel.
          _pendingModel.remove(progress.taskId);
        case DownloadState.queued:
        case DownloadState.running:
        case DownloadState.paused:
        case DownloadState.verifying:
          break;
      }
      return;
    }

    final projectorPairing = _pendingProjector[progress.taskId];
    if (projectorPairing == null) return;
    switch (progress.state) {
      case DownloadState.complete:
        _pendingProjector.remove(progress.taskId);
        unawaited(_attachProjector(projectorPairing, progress.fileName));
      case DownloadState.failed:
      case DownloadState.canceled:
        _pendingProjector.remove(progress.taskId);
        // The model's row already exists (isVision: true, mmprojPath: null)
        // from its own completion — that IS the surfaced "needs projector"
        // half-state; nothing further to write. Surface the failure under
        // the model's taskId so the quant tile's existing error slot shows
        // it (a retry re-runs `enqueueVisionQuant` from scratch).
        final errors = {...state.errors};
        errors[projectorPairing.modelTaskId] =
            progress.failure ??
            NetworkUnknownFailure(
              progress.errorMessage ?? 'projector download failed',
            );
        state = DownloadActionsState(
          pendingTaskIds: state.pendingTaskIds,
          errors: errors,
        );
      case DownloadState.queued:
      case DownloadState.running:
      case DownloadState.paused:
      case DownloadState.verifying:
        break;
    }
  }

  Future<void> _enqueueProjector(_ProjectorPairing pairing) async {
    final manager = await ref.read(downloadManagerProvider.future);
    final request = DownloadRequest(
      repoId: pairing.repoId,
      fileName: p.basename(pairing.mmproj.path),
      url: ref
          .read(hfApiClientProvider)
          .resolveDownloadUrl(pairing.repoId, pairing.mmproj.path),
      expectedSizeBytes: pairing.mmproj.sizeBytes,
      expectedSha256: pairing.mmproj.sha256,
      license: pairing.license.license,
      gated: pairing.license.requiresAuth,
      registerAsInstalledModel: false,
    );
    _pendingProjector[request.taskId] = pairing;
    try {
      final storageInfo = await ref
          .read(deviceInfoServiceProvider)
          .getStorageInfo();
      await manager.enqueue(request, freeBytes: storageInfo.freeBytes);
    } on AppFailure catch (e) {
      _pendingProjector.remove(request.taskId);
      final errors = {...state.errors, pairing.modelTaskId: e};
      state = DownloadActionsState(
        pendingTaskIds: state.pendingTaskIds,
        errors: errors,
      );
    }
  }

  Future<void> _attachProjector(
    _ProjectorPairing pairing,
    String projectorFileName,
  ) async {
    final modelsDir = await ref.read(modelsDirectoryProvider.future);
    final mmprojPath = p.join(modelsDir.path, projectorFileName);
    await ref
        .read(storageManagerProvider)
        .attachProjector(
          repoId: pairing.repoId,
          fileName: pairing.modelFileName,
          mmprojPath: mmprojPath,
        );
  }

  void _finish(String taskId, {AppFailure? error}) {
    final pending = {...state.pendingTaskIds}..remove(taskId);
    final errors = {...state.errors};
    if (error != null) {
      errors[taskId] = error;
    } else {
      errors.remove(taskId);
    }
    state = DownloadActionsState(pendingTaskIds: pending, errors: errors);
  }
}
