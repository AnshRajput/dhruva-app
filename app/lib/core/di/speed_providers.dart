/// Shared plumbing for the on-device speed test: who is using the single
/// engine right now, where results are stored, and the cached results map
/// that both the Models hub and the chat model picker read.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/benchmark/speed_result.dart';

/// Tracks who is using the app-wide singleton engine (ADR-001: one active
/// session). Three kinds of user, in priority order:
///  - chat/playground ([chatEnter]/[chatLeave]): always wins;
///  - a speed test ([tryStartSpeedTest]): refused while chat is busy;
///  - one background user at a time (morning brief, inbox summaries) via
///    [tryEnterBackground]: refused while chat or a speed test is busy, and
///    told to stop ([BackgroundHold.preempted] + its `onPreempt`) the moment
///    chat wants the engine, so a chat send never sees "busy".
/// A plain object (not provider state) so callers can hold it past provider
/// disposal.
final class EngineLease {
  int _chatUsers = 0;
  bool _speedTest = false;
  BackgroundHold? _background;

  /// True while any chat/playground turn or model load is in flight.
  bool get chatBusy => _chatUsers > 0;
  bool get speedTestRunning => _speedTest;
  bool get backgroundBusy => _background != null;

  void chatEnter() => _chatUsers++;
  void chatLeave() {
    if (_chatUsers > 0) _chatUsers--;
  }

  /// Claims the engine for background work. Null when chat, a speed test or
  /// another background user has it. Synchronous, so there is no gap between
  /// the check and the claim. [onPreempt] must make the holder stop using the
  /// engine (cancel its generation); the holder then calls
  /// [BackgroundHold.release].
  BackgroundHold? tryEnterBackground(void Function() onPreempt) {
    if (chatBusy || _speedTest || _background != null) return null;
    return _background = BackgroundHold._(this, onPreempt);
  }

  /// Chat wants the engine: tell the background holder to yield, then wait
  /// for it to let go (at most [grace]). Call after [chatEnter] so no new
  /// background user can start meanwhile.
  Future<void> preemptBackground({
    Duration grace = const Duration(seconds: 1),
  }) async {
    final hold = _background;
    if (hold == null) return;
    hold._preempt();
    await hold._released.future.timeout(grace, onTimeout: () {});
  }

  /// Claims the engine for a speed test; false if chat is using it or a test
  /// is already running. Background work is told to yield.
  bool tryStartSpeedTest() {
    if (_speedTest || chatBusy) return false;
    _speedTest = true;
    _background?._preempt();
    return true;
  }

  void endSpeedTest() => _speedTest = false;
}

/// A background user's claim on the engine (see [EngineLease]).
final class BackgroundHold {
  BackgroundHold._(this._lease, this._onPreempt);
  final EngineLease _lease;
  final void Function() _onPreempt;
  final _released = Completer<void>();
  bool _preempted = false;

  /// True once chat (or a speed test) asked this holder to stop. Check after
  /// every await; when set, stop and [release] without counting a failure.
  bool get preempted => _preempted;

  void _preempt() {
    if (_preempted) return;
    _preempted = true;
    try {
      _onPreempt();
    } catch (_) {}
  }

  void release() {
    if (_released.isCompleted) return;
    if (identical(_lease._background, this)) _lease._background = null;
    _released.complete();
  }
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
