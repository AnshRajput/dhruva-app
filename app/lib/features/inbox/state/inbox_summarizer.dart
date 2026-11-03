/// Lazy one-line summaries for Inbox rows, written by the on-device model.
///
/// Rules (spec section 8, "Lazy summaries vs battery"):
///  - only for rows currently on screen (a row asks when it is built and
///    withdraws when it goes away), never in bulk;
///  - only while the app is in the foreground (a backgrounded app stops, and
///    resumes on return) AND the Inbox is the visible screen (the tab branch
///    stays mounted off screen, so rows alone prove nothing);
///  - never while a chat or a speed test holds the engine, and it yields
///    within about a second when chat asks for it (the engine lease);
///  - one at a time, cached in `items.summary`, so each row is summarised once.
///
/// The notification text is untrusted: it goes to the model only inside the
/// delimited sources block, and the output is shown as text, never acted on.
/// Inference runs in the engine's isolate, not here.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/connector_providers.dart';
import '../../../core/di/engine_session.dart' show loadedModelIdProvider;
import '../../../core/di/providers.dart';
import '../../../core/di/speed_providers.dart';
import '../../../data/connectors/connector.dart';
import '../../../data/connectors/otp_guard.dart' show otpFlag;
import '../../../data/connectors/sources_block.dart';
import '../../../engine_bindings/engine_service.dart';
import '../../today/state/brief_grounding.dart' show ungrounded;

/// Instruction for the model: one short line, quoted data only.
const summaryInstruction =
    'You write a one-line summary of a notification from a phone. Reply with '
    'one short sentence of at most 14 words that says what it is about or '
    'what is being asked. No quotes, no preamble.';

/// Cleans model output into one display line, or null when nothing usable.
///
/// With a [source], a summary that uses a number or capitalised word the
/// source lacks is replaced by the source's first sentence (small models
/// invent), trimmed to the row length.
String? cleanSummary(String raw, {String? source}) {
  var s = raw.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();
  s = s
      .split('\n')
      .map((l) => l.trim())
      .firstWhere((l) => l.isNotEmpty, orElse: () => '');
  s = s.replaceAll(RegExp(r'''^["'`*_\-•\s]+|["'`*_\s]+$'''), '').trim();
  if (s.isEmpty) return null;
  if (source != null && ungrounded(s, source, lenient: true) != null) {
    s = source.trim().split(RegExp(r'(?<=[.?!])\s+|\n+')).first.trim();
    if (s.isEmpty) return null;
  }
  return _row(s);
}

String _row(String s) =>
    s.length > 120 ? '${s.substring(0, 119).trimRight()}…' : s;

class InboxSummarizer with WidgetsBindingObserver {
  InboxSummarizer(this._ref, {bool Function()? isForeground})
    : _isForeground =
          isForeground ??
          (() {
            final s = WidgetsBinding.instance.lifecycleState;
            return s == null || s == AppLifecycleState.resumed;
          }) {
    WidgetsBinding.instance.addObserver(this);
  }

  final Ref _ref;
  final bool Function() _isForeground;
  final _wanted = <int, ConnectorItem>{};
  bool _running = false;
  bool _paused = false;
  bool _disposed = false;
  Timer? _retry;
  BackgroundHold? _hold;

  // Which Inbox screens are on top right now (H2). Hidden owners count only
  // when no screen is shown, and with no screen registered at all the
  // summarizer is not held back (the rows that call it exist only inside one).
  final _shown = <Object>{};
  final _hidden = <Object>{};
  bool get _visible => _shown.isNotEmpty || _hidden.isEmpty;

  /// An Inbox screen ([owner]) became the visible route, or stopped being it
  /// (another tab, covered). Hidden: stop writing now; visible: resume.
  void setVisible(Object owner, bool visible) {
    if (_disposed) return;
    (visible ? _hidden : _shown).remove(owner);
    (visible ? _shown : _hidden).add(owner);
    if (visible) {
      unawaited(_pump());
    } else if (!_visible && _running) {
      _cancelOwn();
    }
  }

  /// The screen is gone for good.
  void forget(Object owner) {
    _shown.remove(owner);
    _hidden.remove(owner);
    if (!_visible && _running) _cancelOwn();
  }

  /// Failed tries per row; a row is given up on after [_maxTries].
  final _tries = <int, int>{};
  static const _maxTries = 3;

  /// Test hook: ids summarised so far, in order.
  final done = <int>[];

  /// A row on screen wants a summary. Ignored when it already has one.
  void request(ConnectorItem item) {
    if (_disposed || item.summary != null || item.body.trim().isEmpty) return;
    // A hidden verification code has nothing left to summarise.
    if (item.flags[otpFlag] == true) return;
    _wanted.putIfAbsent(item.id, () => item);
    unawaited(_pump());
  }

  /// The row went away (scrolled off, screen left): drop its request.
  void cancel(int itemId) {
    _wanted.remove(itemId);
    _tries.remove(itemId);
  }

  /// Stops work and holds new requests until [resume] (the user opened a row
  /// or a chat on top of the Inbox, which now needs the engine).
  void pause() {
    _paused = true;
    if (_running) _cancelOwn();
  }

  void resume() {
    _paused = false;
    unawaited(_pump());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_pump());
    } else if (_running) {
      _cancelOwn();
    }
  }

  void dispose() {
    _disposed = true;
    _retry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _wanted.clear();
  }

  Future<void> _pump() async {
    if (_running || _disposed) return;
    _running = true;
    var weLoaded = false;
    final engine = _ref.read(engineServiceProvider);
    final lease = _ref.read(engineLeaseProvider);
    try {
      while (_canWork) {
        // One background claim per row, taken synchronously (no gap for chat
        // to slip into). Refused while chat or a speed test has the engine.
        final hold = lease.tryEnterBackground(() => unawaited(engine.cancel()));
        if (hold == null) {
          _retryLater();
          break;
        }
        _hold = hold;
        // The row stays wanted until it is written or given up on: a
        // summary cut short (app backgrounded, row opened, chat started) or a
        // failed one is tried again, not lost for the rest of the session.
        final item = _wanted.values.first;
        var failed = false;
        try {
          final models = await _ref
              .read(storageManagerProvider)
              .listTextModels();
          if (models.isEmpty) {
            _wanted.clear(); // nothing to write with: rows keep their text
            break;
          }
          if (hold.preempted) {
            _retryLater();
            break;
          }
          final model = models.first;
          // A model somebody else loaded is used as it is; loading another
          // would evict it for a one-line summary.
          if (!engine.isLoaded) {
            await engine.load(
              model.localPath,
              params: EngineLoadParams(mmprojPath: model.mmprojPath),
            );
            weLoaded = true;
            // Chat asked for the engine while this was loading: the load is
            // left alone (chat's own load shares it) and nothing else is run.
            if (hold.preempted) {
              _retryLater();
              break;
            }
            await _ref.read(storageManagerProvider).touchLastUsed(model.id);
            _ref.read(loadedModelIdProvider.notifier).set(model.id);
          }
          final text = await _summarise(engine, item);
          if (hold.preempted) {
            _retryLater(); // yielded to chat: not a failure, try again later
            break;
          }
          if (text != null && _wanted.containsKey(item.id)) {
            await _ref
                .read(connectorStoreProvider)
                .setSummary(item.id, text, model.fileName);
            done.add(item.id);
            _wanted.remove(item.id);
            _tries.remove(item.id);
          } else if (text == null && _canWork) {
            failed = true; // empty output (not a pause or a backgrounding)
          }
        } catch (e) {
          // A failed, cancelled or timed-out summary leaves the raw text
          // showing; make sure our own generation is not left running (never
          // chat's: after a preempt the engine is not ours to cancel).
          debugPrint('InboxSummarizer: $e');
          if (hold.preempted) {
            _retryLater();
            break;
          }
          failed = true;
          try {
            await engine.cancel();
          } catch (_) {}
        } finally {
          _hold = null;
          hold.release();
        }
        if (failed) {
          final n = (_tries[item.id] ?? 0) + 1;
          _tries[item.id] = n;
          if (n >= _maxTries) {
            _wanted.remove(item.id);
          } else if (_wanted.containsKey(item.id)) {
            _retryLater();
          }
          break; // later rows wait for the retry; no hot loop on a bad model
        }
      }
    } finally {
      _running = false;
      // Do not hold a model in memory just because the Inbox was opened; a
      // model somebody else loaded is left alone.
      if (weLoaded &&
          _wanted.isEmpty &&
          !lease.chatBusy &&
          !lease.speedTestRunning) {
        try {
          await engine.unload();
          _ref.read(loadedModelIdProvider.notifier).set(null);
        } catch (_) {}
      }
    }
  }

  /// Work may run: something is wanted, the Inbox is the visible screen, the
  /// app is resumed, and nobody paused us.
  bool get _canWork =>
      _wanted.isNotEmpty &&
      !_disposed &&
      !_paused &&
      _visible &&
      _isForeground();

  void _retryLater() {
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 10), () => unawaited(_pump()));
  }

  /// Stops our own in-flight generation (never one that is no longer ours).
  void _cancelOwn() {
    final h = _hold;
    if (h != null && !h.preempted) {
      unawaited(_ref.read(engineServiceProvider).cancel());
    }
  }

  Future<String?> _summarise(EngineService engine, ConnectorItem item) async {
    final block = buildSourcesBlock([item], maxChars: 1800, maxItemChars: 1500);
    final out = StringBuffer();
    final stream = engine
        .generate(
          messages: [
            const ChatTurn.system(summaryInstruction),
            ChatTurn.user('${block.text}\n\nSummary:'),
          ],
          params: const EngineGenerateParams(maxTokens: 48, temperature: 0.2),
        )
        .timeout(const Duration(seconds: 45));
    await for (final e in stream) {
      if (e is EngineToken) out.write(e.text);
      if (e is EngineCompletion && e.reason == EngineStopReason.cancelled) {
        return null;
      }
    }
    return cleanSummary(
      out.toString(),
      source: [
        item.title,
        item.body,
        ...item.people.map((p) => p.name),
      ].join('\n'),
    );
  }
}

final inboxSummarizerProvider = Provider<InboxSummarizer>((ref) {
  final s = InboxSummarizer(ref);
  ref.onDispose(s.dispose);
  return s;
});
