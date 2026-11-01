/// Lazy one-line summaries for Inbox rows, written by the on-device model.
///
/// Rules (spec section 8, "Lazy summaries vs battery"):
///  - only for rows currently on screen (a row asks when it is built and
///    withdraws when it goes away), never in bulk;
///  - only while the app is in the foreground (a backgrounded app stops, and
///    resumes on return);
///  - never while a chat or a speed test holds the engine;
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
import '../../../data/connectors/sources_block.dart';
import '../../../engine_bindings/engine_service.dart';

/// Instruction for the model: one short line, quoted data only.
const summaryInstruction =
    'You write a one-line summary of a notification from a phone. Reply with '
    'one short sentence of at most 14 words that says what it is about or '
    'what is being asked. No quotes, no preamble.';

/// Cleans model output into one display line, or null when nothing usable.
String? cleanSummary(String raw) {
  var s = raw.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();
  s = s
      .split('\n')
      .map((l) => l.trim())
      .firstWhere((l) => l.isNotEmpty, orElse: () => '');
  s = s.replaceAll(RegExp(r'''^["'`*_\-•\s]+|["'`*_\s]+$'''), '').trim();
  if (s.isEmpty) return null;
  if (s.length > 120) s = '${s.substring(0, 119).trimRight()}…';
  return s;
}

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

  /// Test hook: ids summarised so far, in order.
  final done = <int>[];

  /// A row on screen wants a summary. Ignored when it already has one.
  void request(ConnectorItem item) {
    if (_disposed || item.summary != null || item.body.trim().isEmpty) return;
    _wanted.putIfAbsent(item.id, () => item);
    unawaited(_pump());
  }

  /// The row went away (scrolled off, screen left): drop its request.
  void cancel(int itemId) => _wanted.remove(itemId);

  /// Stops work and holds new requests until [resume] (the user opened a row
  /// or a chat on top of the Inbox, which now needs the engine).
  void pause() {
    _paused = true;
    if (_running) unawaited(_ref.read(engineServiceProvider).cancel());
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
      unawaited(_ref.read(engineServiceProvider).cancel());
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
      while (_wanted.isNotEmpty && !_disposed && !_paused && _isForeground()) {
        if (lease.chatBusy || lease.speedTestRunning) {
          // The engine is in use: try again shortly instead of queueing up.
          _retry?.cancel();
          _retry = Timer(const Duration(seconds: 10), () => unawaited(_pump()));
          break;
        }
        final item = _wanted.values.first;
        _wanted.remove(item.id);
        lease.chatEnter();
        try {
          final models = await _ref
              .read(storageManagerProvider)
              .listInstalledModels();
          if (models.isEmpty) {
            _wanted.clear(); // nothing to write with: rows keep their text
            break;
          }
          final model = models.first;
          if (!engine.isLoaded ||
              _ref.read(loadedModelIdProvider) != model.id) {
            await engine.load(model.localPath);
            _ref.read(loadedModelIdProvider.notifier).set(model.id);
            weLoaded = true;
          }
          final text = await _summarise(engine, item);
          if (text != null) {
            await _ref
                .read(connectorStoreProvider)
                .setSummary(item.id, text, model.fileName);
            done.add(item.id);
          }
        } catch (_) {
          // A failed, cancelled or timed-out summary just leaves the raw text
          // showing; make sure the engine is not left generating.
          try {
            await engine.cancel();
          } catch (_) {}
        } finally {
          lease.chatLeave();
        }
      }
    } finally {
      _running = false;
      // Do not hold a model in memory just because the Inbox was opened; a
      // model somebody else loaded is left alone.
      if (weLoaded && _wanted.isEmpty && !lease.chatBusy) {
        try {
          await engine.unload();
          _ref.read(loadedModelIdProvider.notifier).set(null);
        } catch (_) {}
      }
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
          params: const EngineGenerateParams(
            maxTokens: 48,
            temperature: 0.2,
            greedy: true,
          ),
        )
        .timeout(const Duration(seconds: 45));
    await for (final e in stream) {
      if (e is EngineToken) out.write(e.text);
      if (e is EngineCompletion && e.reason == EngineStopReason.cancelled) {
        return null;
      }
    }
    return cleanSummary(out.toString());
  }
}

final inboxSummarizerProvider = Provider<InboxSummarizer>((ref) {
  final s = InboxSummarizer(ref);
  ref.onDispose(s.dispose);
  return s;
});
