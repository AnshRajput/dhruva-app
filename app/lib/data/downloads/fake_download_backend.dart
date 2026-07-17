import 'dart:async';

import 'download_backend.dart';

/// Simulates the on-device persistent state a real [DownloadBackend] keeps
/// across app restarts (background_downloader's own SQLite task-tracking
/// database, activated by `trackTasks`). Two [FakeDownloadBackend]s can
/// share one of these to simulate "manager A enqueues, then the app is
/// killed before it completes; manager B is a fresh process that rehydrates
/// from the same on-disk state manager A's plugin would have written."
final class FakeBackendPersistentState {
  final Map<String, String> metaDataByTaskId = {};
}

/// In-memory [DownloadBackend] for tests. Tracks calls and lets the test
/// push synthetic [BackendUpdate]s to drive [DownloadManager] the same way
/// the real plugin's status/progress stream would — without touching a
/// platform channel.
final class FakeDownloadBackend implements DownloadBackend {
  final _controller = StreamController<BackendUpdate>.broadcast();
  final Map<String, BackendDownloadRequest> enqueuedRequests = {};
  final Map<String, String> filePaths = {};
  final List<String> pauseCalls = [];
  final List<String> resumeCalls = [];
  final List<String> cancelCalls = [];
  final FakeBackendPersistentState persistentState;

  /// Set to false to simulate the plugin rejecting an enqueue.
  bool enqueueResult = true;

  FakeDownloadBackend({FakeBackendPersistentState? persistentState})
    : persistentState = persistentState ?? FakeBackendPersistentState();

  @override
  Stream<BackendUpdate> get updates => _controller.stream;

  @override
  Future<bool> enqueue(BackendDownloadRequest request) async {
    enqueuedRequests[request.taskId] = request;
    persistentState.metaDataByTaskId[request.taskId] = request.metaData;
    return enqueueResult;
  }

  @override
  Future<bool> pause(String taskId) async {
    pauseCalls.add(taskId);
    return true;
  }

  @override
  Future<bool> resume(String taskId) async {
    resumeCalls.add(taskId);
    return true;
  }

  @override
  Future<bool> cancel(String taskId) async {
    cancelCalls.add(taskId);
    return true;
  }

  @override
  Future<String?> filePathFor(String taskId) async => filePaths[taskId];

  @override
  Future<List<RehydratedTask>> rehydrate() async {
    return persistentState.metaDataByTaskId.entries
        .map((e) => RehydratedTask(taskId: e.key, metaData: e.value))
        .toList();
  }

  /// Test-only: push a synthetic update onto [updates], as the real plugin
  /// would from its own platform-channel callback.
  void emit(BackendUpdate update) => _controller.add(update);

  Future<void> dispose() => _controller.close();
}
