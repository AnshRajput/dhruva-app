/// Storage/installed screen state (T5 §5): installed models + total usage,
/// delete-with-confirmation, and local GGUF import — all against
/// `StorageManager`/`importLocalGguf` (never drift/dart:io details leak
/// past this file into `ui/`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/di/providers.dart';
import '../../../core/failures/app_failure.dart';
import '../../../data/benchmark/speed_result.dart';
import '../../../data/downloads/local_import.dart';
import '../../../data/downloads/model_file_channel.dart';
import '../../../data/downloads/storage_manager.dart';
import 'speed_test_controller.dart';

final class StorageState {
  final List<InstalledModelInfo> installed;
  final int totalBytes;

  /// Last delete/import failure, surfaced honestly rather than swallowed.
  /// Cleared on the next successful action.
  final AppFailure? actionError;

  /// File name + 0..1 progress of an in-flight import, null when idle.
  final String? importingName;
  final double importProgress;

  const StorageState({
    required this.installed,
    required this.totalBytes,
    this.actionError,
    this.importingName,
    this.importProgress = 0,
  });
}

final storageControllerProvider =
    AsyncNotifierProvider<StorageController, StorageState>(
      StorageController.new,
    );

class StorageController extends AsyncNotifier<StorageState> {
  @override
  Future<StorageState> build() => _load();

  Future<StorageState> _load() async {
    final manager = ref.watch(storageManagerProvider);
    // Loop 6: voice models (`sherpa-voice/` repoId prefix) get their own
    // "Voice" tab (`voice_models_controller.dart`) with install/delete UI
    // that understands their archive-then-extract layout — this tab stays
    // GGUF-only rather than mixing in rows a "Delete" here can't fully
    // clean up (the installer's extracted `models/voice/<id>/` directory
    // isn't touched by `StorageManager.delete`).
    final items = (await manager.listInstalledModels())
        .where((m) => !m.repoId.startsWith('sherpa-voice/'))
        .toList();
    final total = items.fold<int>(0, (sum, m) => sum + m.sizeBytes);
    return StorageState(installed: items, totalBytes: total);
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  Future<void> delete(int id) async {
    try {
      await ref.read(storageManagerProvider).delete(id);
      state = await AsyncValue.guard(_load);
    } on AppFailure catch (e) {
      _setActionError(e);
    }
  }

  ImportCancelToken? _cancel;

  /// True if importing [fileName] would overwrite a file already in the
  /// models directory (UI offers replace-or-skip first).
  Future<bool> importExists(String fileName) async {
    final dir = await ref.read(modelsDirectoryProvider.future);
    return localImportExists(dir, fileName);
  }

  void cancelImport() => _cancel?.cancel();

  /// Opens the system picker. Null when the user cancels, or when the pick
  /// isn't a `.gguf` / the picker failed (then [StorageState.actionError] says
  /// why). Nothing is read or copied here.
  Future<PickedModelFile?> pickModelFile() async {
    try {
      final picked = await ref.read(modelFileChannelProvider).pick();
      if (picked == null) return null;
      if (!picked.name.toLowerCase().endsWith('.gguf')) {
        _setActionError(
          const StorageCorruptFileFailure('selected file is not a .gguf'),
        );
        return null;
      }
      return picked;
    } on ModelFileException catch (e) {
      _setActionError(StorageIoFailure(e.message, cause: e));
      return null;
    }
  }

  /// [picked] came from [pickModelFile]. Streams the copy natively with
  /// progress, validates, and surfaces typed failures instead of crashing.
  /// A user cancel is silent (the partial file is already removed).
  Future<void> importLocal(PickedModelFile picked) async {
    final current = state.value;
    if (current == null || _cancel != null) return;
    final token = _cancel = ImportCancelToken();
    final name = picked.name;
    var lastPct = -1;
    void publish(double progress) {
      state = AsyncData(
        StorageState(
          installed: current.installed,
          totalBytes: current.totalBytes,
          importingName: name,
          importProgress: progress,
        ),
      );
    }

    publish(0);
    try {
      final db = ref.read(appDatabaseProvider);
      final modelsDirectory = await ref.read(modelsDirectoryProvider.future);
      final storage = await ref
          .read(deviceInfoServiceProvider)
          .getStorageInfo();
      final imported = await importLocalGguf(
        picked: picked,
        channel: ref.read(modelFileChannelProvider),
        modelsDirectory: modelsDirectory,
        db: db,
        repoId: 'local/${p.basenameWithoutExtension(picked.name)}',
        freeBytes: storage.freeBytes,
        cancel: token,
        onProgress: (copied, total) {
          final pct = total == 0 ? 100 : copied * 100 ~/ total;
          if (pct == lastPct) return; // don't rebuild per 64KB chunk
          lastPct = pct;
          publish(pct / 100);
        },
      );
      state = await AsyncValue.guard(_load);
      ref
          .read(speedTestOfferProvider.notifier)
          .offer(speedKey(imported.repoId, imported.fileName));
    } on ImportCancelled {
      state = await AsyncValue.guard(_load);
    } on AppFailure catch (e) {
      state = await AsyncValue.guard(_load);
      _setActionError(e);
    } catch (e) {
      // Anything unexpected (device-info / DB errors) must still clear the
      // "importing" banner, or the UI sticks mid-import forever.
      state = await AsyncValue.guard(_load);
      _setActionError(StorageUnknownFailure('import failed: $e'));
    } finally {
      _cancel = null;
    }
  }

  void _setActionError(AppFailure error) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      StorageState(
        installed: current.installed,
        totalBytes: current.totalBytes,
        actionError: error,
      ),
    );
  }
}
