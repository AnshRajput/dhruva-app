/// Runs the brief: cache first, then (only in the foreground) write a fresh
/// one from the fact list.
///
/// When it writes:
///  * on open, if the cached brief is older than 3 h or from another day
///    (and the battery/heat guard has no objection),
///  * on pull-to-refresh,
///  * when the user taps regenerate / "Write my brief".
/// Never in the background, and never on its own when the battery is low.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/device_health/device_guard_policy.dart';
import '../../../core/device_health/device_health.dart';
import '../../../core/device_health/device_health_provider.dart';
import '../../../core/settings/prefs_store.dart';
import 'brief_cache.dart';
import 'brief_prompt.dart';
import 'brief_writer.dart';
import 'today_data.dart';

final class BriefState {
  const BriefState({
    this.brief,
    this.model = BriefModelStatus.none,
    this.writing = false,
    this.warming = false,
    this.error,
  });

  final WrittenBrief? brief;
  final BriefModelStatus model;

  /// A brief is being written right now.
  final bool writing;

  /// The model is loading into memory first.
  final bool warming;

  /// What went wrong and the fix, user-ready; null when all is well.
  final String? error;

  BriefState copyWith({
    WrittenBrief? brief,
    bool clearBrief = false,
    BriefModelStatus? model,
    bool? writing,
    bool? warming,
    String? error,
    bool clearError = false,
  }) => BriefState(
    brief: clearBrief ? null : (brief ?? this.brief),
    model: model ?? this.model,
    writing: writing ?? this.writing,
    warming: warming ?? this.warming,
    error: clearError ? null : (error ?? this.error),
  );
}

final briefCacheStoreProvider = FutureProvider<BriefCacheStore>((ref) async {
  return BriefCacheStore(await ref.watch(prefsStoreProvider.future));
});

final briefControllerProvider =
    AsyncNotifierProvider<BriefController, BriefState>(BriefController.new);

class BriefController extends AsyncNotifier<BriefState> {
  /// Runs [body], ignoring the failure of a pass that was still in flight when
  /// this provider was replaced (the app shell invalidates it when a download
  /// completes, and Today may be mid-write).
  Future<void> _guard(Future<void> Function() body) async {
    try {
      await body();
    } on Object {
      if (ref.mounted) rethrow;
    }
  }

  @override
  Future<BriefState> build() async {
    try {
      return await _build();
    } on Object {
      if (ref.mounted) rethrow;
      return const BriefState();
    }
  }

  Future<BriefState> _build() async {
    BriefCacheStore? cache;
    try {
      cache = await ref.watch(briefCacheStoreProvider.future);
    } on Object {
      cache = null;
    }
    final brief = await cache?.read();
    var model = BriefModelStatus.none;
    try {
      model = await ref.read(briefWriterProvider).status();
    } on Object {
      // Unknown model state reads as "none": facts show, nothing breaks.
    }
    return BriefState(brief: brief, model: model);
  }

  BriefState get _s => state.value ?? const BriefState();

  /// Today opened (or the app came back to the foreground): write a new brief
  /// only if the cached one is stale and nothing argues against it.
  Future<void> onOpen() => _guard(_onOpen);

  Future<void> _onOpen() async {
    await future;
    final cur = _s;
    if (cur.writing) return;
    final now = ref.read(todayClockProvider)();
    final cached = cur.brief;
    if (cached != null && isBriefFresh(cached, now)) return;
    if (ref.read(briefFactsProvider).isEmpty) return;
    if (cur.model == BriefModelStatus.none) return;
    if (!await _mayWriteUnasked()) return;
    await _regenerate();
  }

  /// Foreground, unprompted writing is held back on a low battery or a hot
  /// phone; an explicit tap is the user's call and always goes ahead.
  Future<bool> _mayWriteUnasked() async {
    final DeviceHealth health;
    try {
      health = await ref.read(deviceHealthServiceProvider).read();
    } on Object {
      return true;
    }
    if (DeviceGuardPolicy.thermalAction(health.thermal) != ThermalAction.none) {
      return false;
    }
    return DeviceGuardPolicy.batteryAdvice(health, alreadyWarned: true) ==
        BatteryAdvice.none;
  }

  /// Writes a new brief now (regenerate tap, pull-to-refresh, "Write my
  /// brief"). Keeps the old brief on screen if this one fails.
  Future<void> regenerate() => _guard(_regenerate);

  Future<void> _regenerate() async {
    await future;
    if (_s.writing) return;
    final facts = ref.read(briefFactsProvider);
    if (facts.isEmpty) {
      state = AsyncData(
        _s.copyWith(error: 'There is nothing on your day to write about yet.'),
      );
      return;
    }
    final writer = ref.read(briefWriterProvider);
    state = AsyncData(_s.copyWith(writing: true, clearError: true));
    try {
      var model = await writer.status();
      if (model == BriefModelStatus.none) {
        state = AsyncData(_s.copyWith(writing: false, model: model));
        return;
      }
      if (model == BriefModelStatus.idle) {
        state = AsyncData(_s.copyWith(warming: true));
        await writer.prepare();
        model = BriefModelStatus.ready;
      }
      state = AsyncData(_s.copyWith(warming: false, model: model));
      final raw = await writer.write(
        system: briefSystemPrompt,
        prompt: buildBriefPrompt(facts),
      );
      final brief = WrittenBrief(
        writtenAt: ref.read(todayClockProvider)(),
        raw: raw,
        facts: facts,
      );
      if (brief.parsed().isEmpty) {
        // Nothing the model said could be tied to a fact: show no summary
        // rather than an unchecked one.
        state = AsyncData(
          _s.copyWith(
            writing: false,
            error:
                "The model's text could not be checked against your day, so "
                'it was dropped. Try again, or read the facts below.',
          ),
        );
        return;
      }
      state = AsyncData(
        _s.copyWith(brief: brief, writing: false, clearError: true),
      );
      try {
        await (await ref.read(briefCacheStoreProvider.future)).write(brief);
      } on Object {
        // A cache write failure only costs a re-write next time.
      }
    } on BriefUnavailable catch (e) {
      state = AsyncData(
        _s.copyWith(writing: false, warming: false, error: e.message),
      );
    } on Object {
      state = AsyncData(
        _s.copyWith(
          writing: false,
          warming: false,
          error: "Couldn't write your brief. Pull down to try again.",
        ),
      );
    }
  }

  /// A source was disconnected: whatever was written from it must go.
  Future<void> forgetDisconnected({
    required bool calendarConnected,
    required bool notificationsConnected,
  }) => _guard(
    () => _forgetDisconnected(
      calendarConnected: calendarConnected,
      notificationsConnected: notificationsConnected,
    ),
  );

  Future<void> _forgetDisconnected({
    required bool calendarConnected,
    required bool notificationsConnected,
  }) async {
    await future;
    final b = _s.brief;
    if (b == null) return;
    if (briefStillAllowed(
      b,
      calendarConnected: calendarConnected,
      notificationsConnected: notificationsConnected,
    )) {
      return;
    }
    state = AsyncData(_s.copyWith(clearBrief: true));
    try {
      await (await ref.read(briefCacheStoreProvider.future)).clear();
    } on Object {
      // Best effort: the in-memory brief is already gone.
    }
  }

  /// Re-reads which model state we are in (after a download finished).
  Future<void> refreshModel() => _guard(_refreshModel);

  Future<void> _refreshModel() async {
    await future;
    try {
      final m = await ref.read(briefWriterProvider).status();
      state = AsyncData(_s.copyWith(model: m));
    } on Object {
      // Keep the last known state.
    }
  }
}
