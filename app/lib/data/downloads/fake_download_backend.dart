import 'dart:async';

import 'download_backend.dart';

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

  /// Set to false to simulate the plugin rejecting an enqueue.
  bool enqueueResult = true;

  @override
  Stream<BackendUpdate> get updates => _controller.stream;

  @override
  Future<bool> enqueue(BackendDownloadRequest request) async {
    enqueuedRequests[request.taskId] = request;
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

  /// Test-only: push a synthetic update onto [updates], as the real plugin
  /// would from its own platform-channel callback.
  void emit(BackendUpdate update) => _controller.add(update);

  Future<void> dispose() => _controller.close();
}
