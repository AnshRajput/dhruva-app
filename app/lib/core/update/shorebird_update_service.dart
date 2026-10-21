import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restart_app/restart_app.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

/// Shorebird code-push, manual only (`auto_update: false` in shorebird.yaml).
///
/// Flow: check -> available -> user taps Update -> downloading ->
/// readyToRestart -> user taps Restart -> the patch loads on the next
/// process start. Nothing here ever restarts the app on its own.
enum ShorebirdPhase {
  idle,
  available,
  downloading,
  readyToRestart,
  failed,

  /// Not a Shorebird build (debug, tests, plain `flutter build`): do nothing.
  unavailable,
}

@immutable
class ShorebirdUpdateState {
  const ShorebirdUpdateState({
    this.phase = ShorebirdPhase.idle,
    this.patch,
    this.snoozedUntil,
    this.manualReopen = false,
  });

  final ShorebirdPhase phase;

  /// Installed patch number, null when running the bare release.
  final int? patch;
  final DateTime? snoozedUntil;

  /// The plugin could not relaunch us.
  final bool manualReopen;

  /// iOS (engine restart does not load a patch) or a failed relaunch: show
  /// "Close and reopen the app" instead of a Restart button.
  bool get reopenByHand =>
      manualReopen || defaultTargetPlatform != TargetPlatform.android;

  bool get hasNudge => switch (phase) {
    ShorebirdPhase.available ||
    ShorebirdPhase.downloading ||
    ShorebirdPhase.readyToRestart ||
    ShorebirdPhase.failed => true,
    _ => false,
  };

  bool snoozed(DateTime now) =>
      snoozedUntil != null && now.isBefore(snoozedUntil!);

  ShorebirdUpdateState copyWith({
    ShorebirdPhase? phase,
    int? patch,
    DateTime? snoozedUntil,
    bool clearSnooze = false,
    bool? manualReopen,
  }) => ShorebirdUpdateState(
    phase: phase ?? this.phase,
    patch: patch ?? this.patch,
    snoozedUntil: clearSnooze ? null : snoozedUntil ?? this.snoozedUntil,
    manualReopen: manualReopen ?? this.manualReopen,
  );
}

const _checkEvery = Duration(minutes: 30);
const _snoozeFor = Duration(hours: 6);

/// Seams so tests never touch the engine or a clock.
final shorebirdUpdaterProvider = Provider<ShorebirdUpdater>(
  (ref) => ShorebirdUpdater(),
);
final shorebirdNowProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Returns true when the process was relaunched (or is about to be).
final shorebirdRestartProvider = Provider<Future<bool> Function()>((ref) {
  return () async {
    // Shorebird loads a patch at process start, so the activity-only relaunch
    // is not enough: RestartMode.process kills and relaunches the process.
    // iOS: the plugin only recreates the Flutter engine in the same process,
    // which does not load the patch, so the UI asks for a manual reopen.
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    final r = await Restart.restartApp(mode: RestartMode.process);
    return r.success;
  };
});

final shorebirdUpdateProvider =
    NotifierProvider<ShorebirdUpdateNotifier, ShorebirdUpdateState>(
      ShorebirdUpdateNotifier.new,
    );

class ShorebirdUpdateNotifier extends Notifier<ShorebirdUpdateState>
    with WidgetsBindingObserver {
  late final ShorebirdUpdater _updater = ref.read(shorebirdUpdaterProvider);
  DateTime? _lastCheck;
  bool _checking = false;

  @override
  ShorebirdUpdateState build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() => WidgetsBinding.instance.removeObserver(this));
    if (!_updater.isAvailable) {
      return const ShorebirdUpdateState(phase: ShorebirdPhase.unavailable);
    }
    scheduleMicrotask(check);
    return const ShorebirdUpdateState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) check();
  }

  DateTime get _now => ref.read(shorebirdNowProvider)();

  /// Throttled to once per 30 min unless [force] (the Settings row).
  /// Returns false only when the check itself failed (offline etc.).
  Future<bool> check({bool force = false}) async {
    if (state.phase == ShorebirdPhase.unavailable ||
        state.phase == ShorebirdPhase.downloading ||
        state.phase == ShorebirdPhase.readyToRestart ||
        _checking) {
      return true;
    }
    final now = _now;
    if (!force &&
        _lastCheck != null &&
        now.difference(_lastCheck!) < _checkEvery) {
      return true;
    }
    _checking = true;
    _lastCheck = now;
    try {
      final status = await _updater.checkForUpdate();
      final patch = (await _updater.readCurrentPatch())?.number;
      state = switch (status) {
        UpdateStatus.outdated => state.copyWith(
          phase: ShorebirdPhase.available,
          patch: patch,
        ),
        UpdateStatus.restartRequired => state.copyWith(
          phase: ShorebirdPhase.readyToRestart,
          patch: patch,
        ),
        UpdateStatus.unavailable => const ShorebirdUpdateState(
          phase: ShorebirdPhase.unavailable,
        ),
        UpdateStatus.upToDate => state.copyWith(
          phase: ShorebirdPhase.idle,
          patch: patch,
        ),
      };
      return true;
    } catch (e) {
      // Offline etc.: say nothing, try again next time.
      debugPrint('Shorebird check failed: $e');
      return false;
    } finally {
      _checking = false;
    }
  }

  /// Explicit user tap only. A manual tap also clears any snooze.
  Future<void> download() async {
    if (state.phase != ShorebirdPhase.available &&
        state.phase != ShorebirdPhase.failed) {
      return;
    }
    state = state.copyWith(
      phase: ShorebirdPhase.downloading,
      clearSnooze: true,
    );
    try {
      await _updater.update();
      state = state.copyWith(phase: ShorebirdPhase.readyToRestart);
    } catch (e) {
      debugPrint('Shorebird download failed: $e');
      state = state.copyWith(phase: ShorebirdPhase.failed);
    }
  }

  /// Explicit user tap only; never called automatically.
  Future<void> restart() async {
    if (state.phase != ShorebirdPhase.readyToRestart) return;
    var ok = false;
    try {
      ok = await ref.read(shorebirdRestartProvider)();
    } catch (e) {
      debugPrint('Shorebird restart failed: $e');
    }
    if (!ok) state = state.copyWith(manualReopen: true);
  }

  /// "Later": hides the nudge for 6 h.
  // ponytail: in memory, so a cold start re-shows it; persist if that nags.
  void snooze() => state = state.copyWith(snoozedUntil: _now.add(_snoozeFor));
}
