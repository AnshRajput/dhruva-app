/// [EngineService] backed by `llama_cpp_dart` (ADR-001, pinned git commit
/// c6e3778), running on a dedicated inference isolate that we own.
///
/// ## Why we own the isolate (and don't use `LlamaEngine`)
///
/// The package ships its own worker isolate (`LlamaEngine`), and it streams
/// tokens correctly off-thread. But at the pinned commit it has **no free
/// path**: its worker `_shutdown` (`lib/src/isolate/worker.dart:850-872`)
/// *deliberately* does NOT dispose the model or context —
///
/// > "We deliberately do NOT dispose the model or context here … The OS
/// >  reclaims memory on process exit; that is good enough for M3."
///
/// and `LlamaEngine.dispose` (`lib/src/isolate/engine.dart:345`) only kills
/// the isolate. `LlamaModel.dispose` (`model.dart:335` → `llama_model_free`)
/// and `LlamaContext.dispose` (`context.dart:399` → `llama_free`) are manual
/// (no `NativeFinalizer`), so killing the isolate never runs them. Measured
/// result: ~167 MB leaked per load/unload/reload cycle (SmolLM2-135M, macOS).
///
/// ADR-001 requires "unload runs the full free sequence (ctx then model)".
/// So we run inference on our OWN long-lived isolate ([_llamaEngineWorker])
/// that reuses the package's synchronous primitives — `LlamaModel`,
/// `LlamaContext`, `LlamaSession` (which itself drives the package `Generator`)
/// — and, crucially, disposes ctx then model on unload. This is not
/// double-wrapping: `LlamaEngine` is bypassed entirely; we use the same
/// off-root-isolate + `SendPort` streaming pattern it uses, minus the leak.
///
/// ## Threading (ADR-001)
///
/// All model load, decode and free run inside [_llamaEngineWorker] via
/// `Isolate.spawn`. The main isolate only posts commands and receives token
/// events over a `SendPort`. Cancellation is cooperative: a `_CancelCommand`
/// sets a per-request flag checked between tokens after a forced event-loop
/// turn (`await Future.delayed(Duration.zero)`), mirroring the package's own
/// cancel fix (`worker.dart:835`) — no isolate kill, no half-freed state.
library;

import 'dart:async';
import 'dart:isolate';

import 'package:llama_cpp_dart/llama_cpp_dart.dart' as llama;

import 'engine_service.dart';

// ---------------------------------------------------------------------------
// Error mapping
// ---------------------------------------------------------------------------

/// Translate any error thrown by `llama_cpp_dart` (or a worker error string)
/// into the [EngineFailure] taxonomy. Worker errors cross the isolate boundary
/// as strings, so we also sniff the text for load / OOM signatures.
EngineFailure mapToEngineFailure(Object error, {StackTrace? stackTrace}) {
  if (error is EngineFailure) return error;

  final text = error.toString();
  final lower = text.toLowerCase();
  bool has(String s) => lower.contains(s);

  final looksOom =
      has('out of memory') ||
      has('oom') ||
      has('failed to allocate') ||
      has('insufficient memory') ||
      has('ggml_backend_alloc') ||
      has('unable to allocate');
  final looksLoad =
      has('modelload') ||
      has('failed to load model') ||
      has('failed to open') ||
      has('unable to load model') ||
      has('llamacontextexception') ||
      has('no such file') ||
      has('failed to load dynamic library');

  if (error is llama.LlamaModelLoadException) {
    return looksOom
        ? EngineOutOfMemoryFailure(error.message, cause: error)
        : EngineLoadFailure(error.message, cause: error);
  }
  if (error is llama.LlamaContextException) {
    return looksOom
        ? EngineOutOfMemoryFailure(error.message, cause: error)
        : EngineLoadFailure(error.message, cause: error);
  }
  if (error is llama.LlamaDecodeException) {
    return EngineDecodeFailure(error.toString(), cause: error);
  }
  if (error is llama.LlamaLibraryException) {
    return looksOom
        ? EngineOutOfMemoryFailure(error.message, cause: error)
        : EngineLoadFailure(error.message, cause: error);
  }
  if (looksOom) return EngineOutOfMemoryFailure(text, cause: error);
  if (looksLoad) return EngineLoadFailure(text, cause: error);
  return EngineUnknownFailure(text, cause: error);
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

final class LlamaEngineService implements EngineService {
  /// Absolute path to `libllama.dylib` / `libllama.so`. When null the worker
  /// resolves symbols from the running process (iOS / macOS xcframework that
  /// Xcode statically linked). On Android pass the basename `'libllama.so'`.
  final String? libraryPath;

  LlamaEngineService({this.libraryPath});

  Isolate? _isolate;
  SendPort? _commandPort;
  ReceivePort? _responsePort;
  StreamSubscription<dynamic>? _responseSub;
  bool _disposed = false;

  int _nextId = 1;

  // Single in-flight generation.
  StreamController<EngineEvent>? _activeController;
  int? _activeId;
  int _activeTokens = 0;
  bool _activeTerminal = false;

  // Pending shutdown handshake.
  Completer<void>? _shutdownCompleter;

  @override
  bool get isLoaded => _isolate != null && !_disposed;

  @override
  Future<void> load(
    String modelPath, {
    EngineLoadParams params = const EngineLoadParams(),
  }) async {
    _throwIfDisposed();
    if (_isolate != null) await unload();

    final response = ReceivePort();
    final ready = Completer<_ReadyMsg>();
    final sub = response.listen((dynamic msg) {
      if (!ready.isCompleted) {
        if (msg is _ReadyMsg) {
          ready.complete(msg);
        } else if (msg is _ErrorMsg) {
          ready.completeError(mapToEngineFailure(msg.message));
        }
        return;
      }
      _handleWorkerMessage(msg);
    });

    try {
      _isolate = await Isolate.spawn<_Bootstrap>(
        _llamaEngineWorker,
        _Bootstrap(
          replyPort: response.sendPort,
          libraryPath: libraryPath,
          modelParams: llama.ModelParams(
            path: modelPath,
            gpuLayers: params.gpuLayers,
          ),
          contextParams: llama.ContextParams(
            nCtx: params.contextSize,
            nBatch: params.batchSize,
            nUbatch: params.batchSize,
          ),
        ),
        errorsAreFatal: true,
        debugName: 'dhruva.engine.worker',
      );
      final r = await ready.future;
      _commandPort = r.commandPort;
      _responsePort = response;
      _responseSub = sub;
    } catch (e, st) {
      await sub.cancel();
      response.close();
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      throw mapToEngineFailure(e, stackTrace: st);
    }
  }

  @override
  Stream<EngineEvent> generate({
    String? prompt,
    List<ChatTurn>? messages,
    EngineGenerateParams params = const EngineGenerateParams(),
  }) {
    if ((prompt == null) == (messages == null)) {
      throw const EngineUnknownFailure(
        'generate requires exactly one of prompt or messages',
      );
    }
    if (!isLoaded) {
      throw const EngineDisposedFailure('no model loaded; call load() first');
    }
    if (_activeController != null) {
      throw const EngineDecodeFailure('a generation is already in flight');
    }

    final id = _nextId++;
    // Closed in _handleWorkerMessage / cancel / unload.
    // ignore: close_sinks
    final controller = StreamController<EngineEvent>();
    _activeController = controller;
    _activeId = id;
    _activeTokens = 0;
    _activeTerminal = false;

    final sampler = params.greedy
        ? const llama.SamplerParams(greedy: true)
        : llama.SamplerParams(
            temperature: params.temperature,
            topK: params.topK,
            topP: params.topP,
          );

    final chat = messages
        ?.map(
          (m) => switch (m.role) {
            EngineRole.system => llama.ChatMessage.system(m.content),
            EngineRole.user => llama.ChatMessage.user(m.content),
            EngineRole.assistant => llama.ChatMessage.assistant(m.content),
          },
        )
        .toList();

    controller.onListen = () {
      _commandPort?.send(
        _GenerateCommand(
          id,
          prompt: prompt,
          messages: chat,
          sampler: sampler,
          maxTokens: params.maxTokens,
        ),
      );
    };
    controller.onCancel = () {
      // Consumer unsubscribed: request a cooperative stop downstream.
      if (_activeId == id) {
        _commandPort?.send(_CancelCommand(_nextId++, targetId: id));
        _clearActive(id);
      }
    };

    return controller.stream;
  }

  void _handleWorkerMessage(dynamic msg) {
    switch (msg) {
      case _TokenMsg():
        if (msg.id != _activeId) return;
        _activeTokens++;
        final c = _activeController;
        if (c != null && !c.isClosed) {
          c.add(EngineToken(tokenId: msg.tokenId, text: msg.text));
        }
      case _DoneMsg():
        if (msg.id != _activeId) return;
        _emitTerminal(msg.reason);
        _closeActive(msg.id);
      case _ErrorMsg():
        if (msg.id != _activeId) return;
        final c = _activeController;
        if (c != null && !c.isClosed) {
          c.addError(mapToEngineFailure(msg.message));
        }
        _closeActive(msg.id);
      case _ShutdownDoneMsg():
        _shutdownCompleter?.complete();
    }
  }

  void _emitTerminal(EngineStopReason reason) {
    if (_activeTerminal) return;
    _activeTerminal = true;
    final c = _activeController;
    if (c != null && !c.isClosed) {
      c.add(EngineCompletion(reason: reason, tokenCount: _activeTokens));
    }
  }

  void _closeActive(int id) {
    if (_activeId != id) return;
    final c = _activeController;
    _clearActive(id);
    if (c != null && !c.isClosed) c.close();
  }

  void _clearActive(int id) {
    if (_activeId != id) return;
    _activeController = null;
    _activeId = null;
  }

  @override
  Future<void> cancel() async {
    final id = _activeId;
    if (id == null) return;
    _commandPort?.send(_CancelCommand(_nextId++, targetId: id));
    // The worker replies with a cancelled _DoneMsg, which drives the terminal
    // event + stream close via _handleWorkerMessage.
  }

  @override
  Future<void> unload() async {
    // Terminate any in-flight generation locally.
    final id = _activeId;
    if (id != null) {
      _emitTerminal(EngineStopReason.cancelled);
      _closeActive(id);
    }

    final isolate = _isolate;
    final commandPort = _commandPort;
    final response = _responsePort;
    final sub = _responseSub;
    _isolate = null;
    _commandPort = null;
    _responsePort = null;
    _responseSub = null;

    if (isolate == null) return;

    // Ask the worker to free ctx + model, then wait for confirmation so the
    // native free actually happens before we drop the isolate.
    final done = Completer<void>();
    _shutdownCompleter = done;
    commandPort?.send(_ShutdownCommand(_nextId++));
    try {
      await done.future.timeout(const Duration(seconds: 5));
    } catch (_) {
      // Fall through: kill regardless so we never wedge.
    }
    _shutdownCompleter = null;
    await sub?.cancel();
    response?.close();
    isolate.kill(priority: Isolate.beforeNextEvent);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await unload();
    _disposed = true;
  }

  void _throwIfDisposed() {
    if (_disposed) {
      throw const EngineDisposedFailure('engine has been disposed');
    }
  }
}

// ---------------------------------------------------------------------------
// Isolate protocol
// ---------------------------------------------------------------------------

final class _Bootstrap {
  final SendPort replyPort;
  final String? libraryPath;
  final llama.ModelParams modelParams;
  final llama.ContextParams contextParams;
  const _Bootstrap({
    required this.replyPort,
    required this.libraryPath,
    required this.modelParams,
    required this.contextParams,
  });
}

sealed class _Command {
  final int id;
  const _Command(this.id);
}

final class _GenerateCommand extends _Command {
  final String? prompt;
  final List<llama.ChatMessage>? messages;
  final llama.SamplerParams sampler;
  final int maxTokens;
  const _GenerateCommand(
    super.id, {
    required this.prompt,
    required this.messages,
    required this.sampler,
    required this.maxTokens,
  });
}

final class _CancelCommand extends _Command {
  final int targetId;
  const _CancelCommand(super.id, {required this.targetId});
}

final class _ShutdownCommand extends _Command {
  const _ShutdownCommand(super.id);
}

final class _ReadyMsg {
  final SendPort commandPort;
  final String? chatTemplate;
  const _ReadyMsg(this.commandPort, this.chatTemplate);
}

final class _TokenMsg {
  final int id;
  final int tokenId;
  final String text;
  const _TokenMsg(this.id, this.tokenId, this.text);
}

final class _DoneMsg {
  final int id;
  final EngineStopReason reason;
  final int tokenCount;
  const _DoneMsg(this.id, this.reason, this.tokenCount);
}

final class _ErrorMsg {
  final int id;
  final String message;
  const _ErrorMsg(this.id, this.message);
}

final class _ShutdownDoneMsg {
  const _ShutdownDoneMsg();
}

// ---------------------------------------------------------------------------
// Worker (runs on the spawned inference isolate)
// ---------------------------------------------------------------------------

/// Entry point for the dedicated inference isolate. Loads the native library,
/// model and context here (never on the root isolate), streams tokens back
/// over [_Bootstrap.replyPort], and — the reason this exists — frees ctx then
/// model on shutdown.
Future<void> _llamaEngineWorker(_Bootstrap boot) async {
  final reply = boot.replyPort;
  final llama.LlamaModel model;
  final llama.LlamaContext context;
  try {
    if (boot.libraryPath == null) {
      llama.LlamaLibrary.loadFromProcess();
    } else {
      llama.LlamaLibrary.load(path: boot.libraryPath!);
    }
    model = llama.LlamaModel.load(boot.modelParams);
    context = llama.LlamaContext.create(model, boot.contextParams);
  } catch (e, st) {
    reply.send(_ErrorMsg(0, '$e\n$st'));
    return;
  }

  final template = llama.ChatTemplate.fromModel(model);
  final session = llama.LlamaSession(context, seqId: 0);
  final cancelled = <int>{};
  final commandRx = ReceivePort();
  final done = Completer<void>();

  reply.send(_ReadyMsg(commandRx.sendPort, template));

  commandRx.listen((dynamic msg) {
    if (msg is _CancelCommand) {
      cancelled.add(msg.targetId);
      return;
    }
    if (msg is _ShutdownCommand) {
      // The full free sequence (ADR-001): KV → context → model → library.
      try {
        session.clear();
      } catch (_) {
        /* ignore */
      }
      try {
        context.dispose(); // llama_free
      } catch (_) {
        /* ignore */
      }
      try {
        model.dispose(); // llama_model_free
      } catch (_) {
        /* ignore */
      }
      llama.LlamaLibrary.dispose();
      reply.send(const _ShutdownDoneMsg());
      commandRx.close();
      done.complete();
      return;
    }
    if (msg is _GenerateCommand) {
      unawaited(_runGenerate(msg, session, template, cancelled, reply));
    }
  });

  await done.future;
}

Future<void> _runGenerate(
  _GenerateCommand cmd,
  llama.LlamaSession session,
  String? template,
  Set<int> cancelled,
  SendPort reply,
) async {
  try {
    // Each call is independent: reset KV + history first.
    session.clear();

    if (cmd.messages != null) {
      if (template == null) {
        reply.send(
          _ErrorMsg(cmd.id, 'model has no chat template; use a prompt instead'),
        );
        return;
      }
      final rendered = llama.ChatTemplate.apply(
        template: template,
        messages: cmd.messages!,
        addAssistant: true,
      );
      session.appendText(rendered, addSpecial: false);
    } else {
      session.appendText(cmd.prompt!, addSpecial: true);
    }

    var count = 0;
    await for (final event in session.generate(
      sampler: cmd.sampler,
      maxTokens: cmd.maxTokens,
    )) {
      // Force one event-loop turn so a pending _CancelCommand is registered
      // between tokens (mirrors llama_cpp_dart worker.dart:835). Without this
      // the microtask-driven generate stream starves the cancel event.
      await Future<void>.delayed(Duration.zero);
      if (cancelled.remove(cmd.id)) {
        reply.send(_DoneMsg(cmd.id, EngineStopReason.cancelled, count));
        return;
      }
      switch (event) {
        case llama.TokenEvent():
          count++;
          if (event.text.isNotEmpty) {
            reply.send(_TokenMsg(cmd.id, event.id, event.text));
          }
        case llama.ShiftEvent():
          break;
        case llama.DoneEvent():
          if (event.trailingText.isNotEmpty) {
            reply.send(_TokenMsg(cmd.id, -1, event.trailingText));
          }
          final reason = switch (event.reason) {
            llama.StopEog() => EngineStopReason.endOfSequence,
            llama.StopMaxTokens() => EngineStopReason.maxTokens,
            llama.StopUserAbort() => EngineStopReason.cancelled,
          };
          reply.send(_DoneMsg(cmd.id, reason, count));
          return;
      }
    }
    reply.send(_DoneMsg(cmd.id, EngineStopReason.endOfSequence, count));
  } catch (e, st) {
    if (cancelled.remove(cmd.id)) {
      reply.send(_DoneMsg(cmd.id, EngineStopReason.cancelled, 0));
    } else {
      reply.send(_ErrorMsg(cmd.id, '$e\n$st'));
    }
  }
}
