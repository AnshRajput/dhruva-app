/// Storage/installed screen state (T5 §5): installed models + total usage,
/// delete-with-confirmation, and local GGUF import — all against
/// `StorageManager`/`importLocalGguf` (never drift/dart:io details leak
/// past this file into `ui/`).
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/di/providers.dart';
import '../../../core/failures/app_failure.dart';
import '../../../data/downloads/local_import.dart';
import '../../../data/downloads/storage_manager.dart';

final class StorageState {
  final List<InstalledModelInfo> installed;
  final int totalBytes;

  /// Last delete/import failure, surfaced honestly rather than swallowed.
  /// Cleared on the next successful action.
  final AppFailure? actionError;

  const StorageState({
    required this.installed,
    required this.totalBytes,
    this.actionError,
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

  /// [sourceFile] is a user-picked GGUF (picked in the UI layer via
  /// `file_selector` — selection itself is a UI concern). Validates via
  /// `importLocalGguf` and surfaces its typed failures instead of crashing.
  Future<void> importLocal(File sourceFile) async {
    try {
      final db = ref.read(appDatabaseProvider);
      final modelsDirectory = await ref.read(modelsDirectoryProvider.future);
      await importLocalGguf(
        sourceFile: sourceFile,
        modelsDirectory: modelsDirectory,
        db: db,
        repoId: 'local/${p.basenameWithoutExtension(sourceFile.path)}',
      );
      state = await AsyncValue.guard(_load);
    } on AppFailure catch (e) {
      _setActionError(e);
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
