/// Runs the OPTIONAL "Rewrite in my words". The brief itself is written by
/// rules (`dayBriefProvider`) and needs no model; this controller only asks the
/// on-device model to reword it, and shows the result only if it passes the
/// strict grounding check (`checkRewrite`).
///
/// When it writes: only when the user taps "Rewrite in my words" (or "Write it
/// again"), only in the foreground, never in the background. A rewrite that
/// fails the check, or any failure, leaves the rule-written brief on screen; a
/// rejected rewrite is never cached.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/prefs_store.dart';
import 'brief_cache.dart';
import 'brief_facts.dart';
import 'brief_grounding.dart';
import 'brief_prompt.dart';
import 'brief_writer.dart';
import 'today_data.dart';

final class BriefState {
  const BriefState({
    this.rewrite,
    this.model = BriefModelStatus.none,
    this.writing = false,
    this.warming = false,
    this.keptChecked = false,
    this.error,
  });

  /// The checked rewrite, if there is one. Whether it still matches today's
  /// facts is decided where it is shown (`shownRewrite`).
  final WrittenBrief? rewrite;
  final BriefModelStatus model;

  /// A rewrite is being written right now.
  final bool writing;

  /// The model is loading into memory first.
  final bool warming;

  /// The last rewrite failed the check and was thrown away.
  final bool keptChecked;

  /// What went wrong and the fix, user-ready; null when all is well.
  final String? error;

  BriefState copyWith({
    WrittenBrief? rewrite,
    bool clearRewrite = false,
    BriefModelStatus? model,
    bool? writing,
    bool? warming,
    bool? keptChecked,
    String? error,
    bool clearError = false,
  }) => BriefState(
    rewrite: clearRewrite ? null : (rewrite ?? this.rewrite),
    model: model ?? this.model,
    writing: writing ?? this.writing,
    warming: warming ?? this.warming,
    keptChecked: keptChecked ?? this.keptChecked,
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
    final rewrite = await cache?.read();
    var model = BriefModelStatus.none;
    try {
      model = await ref.read(briefWriterProvider).status();
    } on Object {
      // Unknown model state reads as "none": the brief shows without it.
    }
    return BriefState(rewrite: rewrite, model: model);
  }

  BriefState get _s => state.value ?? const BriefState();

  /// Today opened (or the app came back to the foreground): forget a cached
  /// rewrite that no longer matches the day. Never writes anything.
  Future<void> onOpen() => _guard(_onOpen);

  Future<void> _onOpen() async {
    await future;
    final facts = ref.read(briefFactsProvider);
    if (facts.isEmpty) return;
    await _dropIfStale(facts);
  }

  /// Drops the rewrite when it was checked against other facts than today's:
  /// it would contradict the screen.
  Future<void> _dropIfStale(List<BriefFact> facts) async {
    final r = _s.rewrite;
    if (r == null || listEquals(r.facts, facts)) return;
    await _forgetRewrite();
  }

  Future<void> _forgetRewrite() async {
    state = AsyncData(_s.copyWith(clearRewrite: true));
    try {
      await (await ref.read(briefCacheStoreProvider.future)).clear();
    } on Object {
      // Best effort: the in-memory rewrite is already gone.
    }
  }

  /// "Show the original": back to the rule-written brief.
  Future<void> useOriginal() => _guard(() async {
    await future;
    state = AsyncData(_s.copyWith(keptChecked: false, clearError: true));
    await _forgetRewrite();
  });

  /// Asks the model to reword the brief now. The result is shown only if EVERY
  /// sentence passes `checkRewrite` against the facts it cites; otherwise it is
  /// thrown away (never cached) and the rule-written brief stays, with
  /// [BriefState.keptChecked] set. A failure leaves whatever was already
  /// shown, which was itself checked.
  Future<void> rewrite() => _guard(_rewrite);

  Future<void> _rewrite() async {
    await future;
    if (_s.writing) return;
    final draft = ref.read(dayBriefProvider);
    if (draft.isEmpty) {
      state = AsyncData(
        _s.copyWith(error: 'There is nothing on your day to reword yet.'),
      );
      return;
    }
    await _dropIfStale(draft.facts);
    final writer = ref.read(briefWriterProvider);
    state = AsyncData(
      _s.copyWith(writing: true, keptChecked: false, clearError: true),
    );
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
        prompt: buildRewritePrompt(draft.sentences),
      );
      // The day moved on while the model wrote (a meeting started, "Mark all
      // read"): the text was checked against facts that are gone.
      if (!ref.mounted ||
          !listEquals(ref.read(briefFactsProvider), draft.facts)) {
        if (ref.mounted) state = AsyncData(_s.copyWith(writing: false));
        return;
      }
      final name = ref.read(todayNameProvider);
      final check = checkRewrite(raw, draft.facts, names: {?name});
      if (!check.ok) {
        state = AsyncData(
          _s.copyWith(writing: false, keptChecked: true, clearRewrite: true),
        );
        try {
          // Whatever an earlier rewrite left cached goes too: the user asked
          // for new words and the checked version is what stays.
          await (await ref.read(briefCacheStoreProvider.future)).clear();
        } on Object {
          // Nothing from this attempt was ever cached.
        }
        return;
      }
      final checked = WrittenBrief(
        writtenAt: ref.read(todayClockProvider)(),
        raw: [
          for (final s in check.sentences) markedSentence(s, forPrompt: false),
        ].join('\n'),
        facts: draft.facts,
      );
      state = AsyncData(
        _s.copyWith(rewrite: checked, writing: false, clearError: true),
      );
      try {
        await (await ref.read(briefCacheStoreProvider.future)).write(checked);
      } on Object {
        // A cache write failure only costs a re-write next time.
      }
    } on BriefUnavailable catch (e) {
      state = AsyncData(
        _s.copyWith(writing: false, warming: false, error: e.message),
      );
    } on Object {
      if (!ref.mounted) return;
      state = AsyncData(
        _s.copyWith(
          writing: false,
          warming: false,
          error: "Couldn't reword your brief. Try again in a moment.",
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
    final b = _s.rewrite;
    if (b == null) return;
    if (briefStillAllowed(
      b,
      calendarConnected: calendarConnected,
      notificationsConnected: notificationsConnected,
    )) {
      return;
    }
    await _forgetRewrite();
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
