/// Voice-model catalog UI state (Loop 6, T4/D4) — the "Voice" tab in
/// `models_hub_screen.dart`. Bridges [voiceModelCatalog] onto the SAME
/// `DownloadManager` [downloads_controller.dart] already uses for GGUF
/// models, plus the archive-extraction step ([VoiceModelInstaller]) GGUF
/// downloads don't need.
///
/// Every entry starts `notInstalled`/`downloading`/`installing`/`installed`/
/// `failed`; `installing` is the (usually sub-second, for the VAD's single
/// small file effectively instant) window between the archive landing on
/// disk and its files being extracted+verified.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/failures/app_failure.dart';
import '../../../data/downloads/download_manager.dart';
import '../../../voice/voice_model_catalog.dart';
import '../../../voice/voice_model_installer.dart';
import '../../../voice/voice_service.dart' show VoiceFailure;

enum VoiceModelStatus {
  notInstalled,
  downloading,
  installing,
  installed,
  failed,
}

final class VoiceModelState {
  final VoiceCatalogEntry entry;
  final VoiceModelStatus status;

  /// 0..1 while [status] is `downloading`; meaningless otherwise.
  final double progress;
  final String? errorMessage;

  const VoiceModelState({
    required this.entry,
    required this.status,
    this.progress = 0,
    this.errorMessage,
  });

  VoiceModelState copyWith({
    VoiceModelStatus? status,
    double? progress,
    String? errorMessage,
    bool clearError = false,
  }) => VoiceModelState(
    entry: entry,
    status: status ?? this.status,
    progress: progress ?? this.progress,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
  );
}

final voiceModelsControllerProvider =
    AsyncNotifierProvider<VoiceModelsController, List<VoiceModelState>>(
      VoiceModelsController.new,
    );

class VoiceModelsController extends AsyncNotifier<List<VoiceModelState>> {
  StreamSubscription<DownloadProgress>? _sub;

  /// Guards [_finishInstall] against a `complete` progress event landing
  /// twice for the same entry (the manager's own stream can replay a
  /// terminal `complete` state — see `download_manager.dart`'s `_emit` doc
  /// — extraction itself is not re-entrant safe, `install()` deletes the
  /// archive it just read).
  final Set<String> _installing = {};

  @override
  Future<List<VoiceModelState>> build() async {
    // `read`, not `watch`: [_finishInstall]/[delete] invalidate
    // `voiceModelInstallerProvider` so the voice FEATURE re-detects a
    // just-installed/deleted model without an app restart. The installer
    // instance only depends on the (stable) models directory and
    // `isInstalled` reads disk live, so watching it here would buy nothing
    // but a full list rebuild that also wipes any sibling entry's in-flight
    // download progress on every invalidation.
    final installer = await ref.read(voiceModelInstallerProvider.future);
    final manager = await ref.watch(downloadManagerProvider.future);
    ref.onDispose(() => unawaited(_sub?.cancel()));
    _sub = manager.progress.listen(_onProgress);
    return [
      for (final entry in voiceModelCatalog)
        VoiceModelState(
          entry: entry,
          status: installer.isInstalled(entry)
              ? VoiceModelStatus.installed
              : VoiceModelStatus.notInstalled,
        ),
    ];
  }

  Future<void> download(VoiceCatalogEntry entry) async {
    _update(entry.id, (s) => s.copyWith(clearError: true));
    try {
      final freeBytes =
          (await ref.read(deviceInfoServiceProvider).getStorageInfo())
              .freeBytes;
      final manager = await ref.read(downloadManagerProvider.future);
      await manager.enqueue(
        voiceModelDownloadRequest(entry),
        freeBytes: freeBytes,
      );
      _update(
        entry.id,
        (s) => s.copyWith(status: VoiceModelStatus.downloading, progress: 0),
      );
    } on AppFailure catch (e) {
      _update(
        entry.id,
        (s) => s.copyWith(
          status: VoiceModelStatus.failed,
          errorMessage: e.message,
        ),
      );
    }
  }

  Future<void> delete(VoiceCatalogEntry entry) async {
    final installer = await ref.read(voiceModelInstallerProvider.future);
    final dir = installer.installDir(entry);
    if (dir.existsSync()) await dir.delete(recursive: true);
    if (!entry.isArchive) {
      for (final path in installer.resolvePaths(entry).values) {
        final f = File(path);
        if (f.existsSync()) await f.delete();
      }
    }
    _update(
      entry.id,
      (s) => s.copyWith(
        status: VoiceModelStatus.notInstalled,
        progress: 0,
        clearError: true,
      ),
    );
    // Mirror install: refresh the shared installer so the voice feature stops
    // offering a model whose files we just removed, without a restart.
    ref.invalidate(voiceModelInstallerProvider);
  }

  void _onProgress(DownloadProgress p) {
    final entry = _entryForTaskId(p.taskId);
    if (entry == null) return;
    switch (p.state) {
      case DownloadState.complete:
        unawaited(_finishInstall(entry));
      case DownloadState.failed:
        _installing.remove(entry.id);
        _update(
          entry.id,
          (s) => s.copyWith(
            status: VoiceModelStatus.failed,
            errorMessage: p.errorMessage ?? 'download failed',
          ),
        );
      case DownloadState.canceled:
        _update(
          entry.id,
          (s) => s.copyWith(status: VoiceModelStatus.notInstalled, progress: 0),
        );
      case DownloadState.queued:
      case DownloadState.running:
      case DownloadState.paused:
      case DownloadState.verifying:
        final total = p.totalBytes ?? entry.downloadSizeBytes;
        final progress = total > 0
            ? (p.downloadedBytes / total).clamp(0.0, 1.0)
            : 0.0;
        _update(
          entry.id,
          (s) => s.copyWith(
            status: VoiceModelStatus.downloading,
            progress: progress,
          ),
        );
    }
  }

  Future<void> _finishInstall(VoiceCatalogEntry entry) async {
    if (_installing.contains(entry.id)) return;
    _installing.add(entry.id);
    _update(entry.id, (s) => s.copyWith(status: VoiceModelStatus.installing));
    try {
      final installer = await ref.read(voiceModelInstallerProvider.future);
      await installer.install(entry);
      _update(entry.id, (s) => s.copyWith(status: VoiceModelStatus.installed));
      // Files are now on disk — drop the cached installer so the voice
      // feature (handsfree / hold-to-talk / TTS playback) re-detects this
      // model on its next use instead of only after an app restart. Same
      // "invalidate installed-model providers on completion" precedent as the
      // GGUF path in `app_shell.dart` (A1/A5).
      ref.invalidate(voiceModelInstallerProvider);
    } on VoiceFailure catch (e) {
      _update(
        entry.id,
        (s) => s.copyWith(
          status: VoiceModelStatus.failed,
          errorMessage: e.message,
        ),
      );
    } catch (e) {
      // QA BUG-1 defense-in-depth: `install()` is now expected to only ever
      // throw a typed `VoiceFailure` (see `extractTarBz2`'s decode
      // wrapping), but a tile stuck on "installing" forever from ANY
      // uncaught error — typed or not — is worse than a generic failed
      // state, so this is a deliberate catch-all, not a silent swallow.
      _update(
        entry.id,
        (s) => s.copyWith(
          status: VoiceModelStatus.failed,
          errorMessage: 'install failed: $e',
        ),
      );
    } finally {
      _installing.remove(entry.id);
    }
  }

  VoiceCatalogEntry? _entryForTaskId(String taskId) {
    for (final entry in voiceModelCatalog) {
      if (voiceModelDownloadRequest(entry).taskId == taskId) return entry;
    }
    return null;
  }

  void _update(
    String entryId,
    VoiceModelState Function(VoiceModelState) transform,
  ) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData([
      for (final s in current)
        if (s.entry.id == entryId) transform(s) else s,
    ]);
  }
}
