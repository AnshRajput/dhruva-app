/// Shared plumbing for the on-device speed test: who is using the single
/// engine right now, where results are stored, and the cached results map
/// that both the Models hub and the chat model picker read.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/benchmark/speed_result.dart';

/// Tracks who is using the app-wide singleton engine (ADR-001: one active
/// session) so a speed test never starts during a chat generation/load and
/// chat never loads a model underneath a running speed test. A plain object
/// (not provider state) so callers can hold it past provider disposal.
final class EngineLease {
  int _chatUsers = 0;
  bool _speedTest = false;

  /// True while any chat/playground turn or model load is in flight.
  bool get chatBusy => _chatUsers > 0;
  bool get speedTestRunning => _speedTest;

  void chatEnter() => _chatUsers++;
  void chatLeave() {
    if (_chatUsers > 0) _chatUsers--;
  }

  /// Claims the engine for a speed test; false if chat is using it or a test
  /// is already running.
  bool tryStartSpeedTest() {
    if (_speedTest || chatBusy) return false;
    _speedTest = true;
    return true;
  }

  void endSpeedTest() => _speedTest = false;
}

final engineLeaseProvider = Provider<EngineLease>((ref) => EngineLease());

/// Stamped into each result. Overridden in `main.dart` with the real version
/// (kept out of core to avoid importing `features/settings`).
final appVersionProvider = Provider<String>((ref) => 'unknown');

final speedResultStoreProvider = FutureProvider<SpeedResultStore>((ref) async {
  final dir = await getApplicationSupportDirectory();
  return SpeedResultStore(File('${dir.path}/speed_results.json'));
});

/// Saved speed results keyed by [speedKey].
final speedResultsProvider =
    AsyncNotifierProvider<SpeedResultsNotifier, Map<String, SpeedResult>>(
      SpeedResultsNotifier.new,
    );

class SpeedResultsNotifier extends AsyncNotifier<Map<String, SpeedResult>> {
  @override
  Future<Map<String, SpeedResult>> build() async {
    final store = await ref.watch(speedResultStoreProvider.future);
    return store.load();
  }

  Future<void> save(String key, SpeedResult result) async {
    final store = await ref.read(speedResultStoreProvider.future);
    await store.put(key, result);
    state = AsyncData({...?state.value, key: result});
  }
}
