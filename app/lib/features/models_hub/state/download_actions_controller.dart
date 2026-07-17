/// Per-file "enqueue a download" action state for the model detail screen
/// (T5 §3). Tracks which task ids are mid-enqueue and the last enqueue
/// failure per task id (free-space guard errors, backend rejection, ...)
/// so each file's Download button renders its own pending/error state
/// without one file's failure clobbering another's.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/failures/app_failure.dart';
import '../../../data/downloads/download_manager.dart';

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

final downloadActionsControllerProvider =
    NotifierProvider<DownloadActionsController, DownloadActionsState>(
      DownloadActionsController.new,
    );

class DownloadActionsController extends Notifier<DownloadActionsState> {
  @override
  DownloadActionsState build() => const DownloadActionsState();

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
