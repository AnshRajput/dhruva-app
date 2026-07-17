/// [ImageGenService] backed by the vendored stable-diffusion.cpp
/// (`engine/sd/vendor/stable-diffusion.cpp` @ b290693, bound via ffigen), on a
/// dedicated worker isolate that WE own — mirroring `LlamaEngineService`.
///
/// ## Why an owned isolate (same discipline as ADR-001)
///
/// `new_sd_ctx` is a multi-GB resident allocation and `generate_image` is a
/// long blocking native call. Both run on [_sdWorker] (never the root isolate),
/// and — the point — `free_sd_ctx` runs on [unload] so that memory is actually
/// reclaimed (proven by the load→unload→reload RSS test). One `sd_ctx_t*` lives
/// at a time.
///
/// ## Cancellation (cross-thread, by design)
///
/// `generate_image` blocks the worker for the whole run, so the worker can't
/// receive a "cancel" message mid-flight. Instead sd.cpp exposes a lock-free
/// `sd_cancel_generation(ctx, SD_CANCEL_ALL)` meant to be called from another
/// thread; its per-step check then makes `generate_image` return early. So
/// [cancel] runs on the MAIN isolate: it flips a shared native flag and calls
/// `sd_cancel_generation` on the ctx pointer directly (both valid process-wide).
/// The worker reads the shared flag to tell a cancelled `false` return from a
/// real error.
///
/// ## One heavy model at a time (RAM gate)
///
/// SD 1.5 peaks ~2-4 GB. [loadModel] refuses (with [ImageGenStateFailure]) when
/// the injected [isOtherHeavyModelResident] predicate says the LLM engine is
/// loaded — the app must unload it first. The device-level floor (feature
/// hidden below [recommendedMinRamBytes]) is an app-shell gate, documented on
/// that constant.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'image_gen_service.dart';
import 'png_encoder.dart';
import 'sd_bindings.g.dart';

/// Open the sd.cpp dylib. Null path → resolve from the running process (iOS /
/// macOS static link); a path → `DynamicLibrary.open` (dev macOS dylib,
/// Android `libstable-diffusion.so` by basename).
DynamicLibrary _openSdLibrary(String? libraryPath) => libraryPath == null
    ? DynamicLibrary.process()
    : DynamicLibrary.open(libraryPath);

/// Best-effort classification of an sd.cpp failure string into the taxonomy.
ImageGenFailure mapToImageGenFailure(Object error) {
  if (error is ImageGenFailure) return error;
  final lower = error.toString().toLowerCase();
  bool has(String s) => lower.contains(s);
  if (has('out of memory') ||
      has('oom') ||
      has('failed to allocate') ||
      has('ggml_backend') ||
      has('unable to allocate')) {
    return ImageGenOutOfMemoryFailure(error.toString(), cause: error);
  }
  if (has('failed to load') ||
      has('no such file') ||
      has('unable to load') ||
      has('failed to open') ||
      has('unsupported')) {
    return ImageGenLoadFailure(error.toString(), cause: error);
  }
  return ImageGenUnknownFailure(error.toString(), cause: error);
}

enum _FailKind { load, oom, decode, validation, unknown }

_FailKind _classify(Object error) => switch (mapToImageGenFailure(error)) {
  ImageGenLoadFailure() => _FailKind.load,
  ImageGenOutOfMemoryFailure() => _FailKind.oom,
  ImageGenDecodeFailure() => _FailKind.decode,
  ImageGenValidationFailure() => _FailKind.validation,
  _ => _FailKind.unknown,
};

ImageGenFailure _failureFromKind(_FailKind kind, String message) =>
    switch (kind) {
      _FailKind.load => ImageGenLoadFailure(message),
      _FailKind.oom => ImageGenOutOfMemoryFailure(message),
      _FailKind.decode => ImageGenDecodeFailure(message),
      _FailKind.validation => ImageGenValidationFailure(message),
      _FailKind.unknown => ImageGenUnknownFailure(message),
    };

final class SdImageGenService implements ImageGenService {
  /// Absolute path to `libstable-diffusion.dylib` / `.so`. Null on iOS/macOS
  /// release (symbols in the process). Android passes the `.so` basename.
  final String? libraryPath;

  /// The app's "another heavy model is resident" check (the loaded LLM). When
  /// it returns true, [loadModel] refuses — one big model at a time. Null in
  /// tests/dev where no coordination is needed.
  final bool Function()? isOtherHeavyModelResident;

  /// Ceiling on the load handshake before giving up (guards a wedged worker).
  final Duration loadTimeout;

  /// Device-RAM floor below which the Imagine feature should stay HIDDEN. SD
  /// 1.5 peaks ~3.6 GB at 384² on desktop; phones can't spare that atop the OS.
  /// The app shell gates on this; the engine itself only enforces the
  /// one-model-at-a-time rule.
  static const int recommendedMinRamBytes = 6 * 1024 * 1024 * 1024;

  SdImageGenService({
    this.libraryPath,
    this.isOtherHeavyModelResident,
    this.loadTimeout = const Duration(seconds: 120),
  });

  Isolate? _isolate;
  SendPort? _commandPort;
  ReceivePort? _responsePort;
  StreamSubscription<dynamic>? _responseSub;
  bool _disposed = false;
  int _nextId = 1;

  // Cross-thread cancel handles (valid process-wide; set from the ready msg).
  int? _ctxAddr;
  int? _cancelFlagAddr;
  SdBindings? _cancelBindings;

  // Single in-flight generation.
  StreamController<ImageGenEvent>? _activeController;
  int? _activeId;
  Stopwatch? _activeStopwatch;

  Completer<void>? _shutdownCompleter;

  @override
  bool get isLoaded => _isolate != null && !_disposed;

  @override
  Future<void> loadModel(
    String modelPath, {
    ImageGenLoadParams params = const ImageGenLoadParams(),
  }) async {
    _throwIfDisposed();
    if (!File(modelPath).existsSync()) {
      throw ImageGenLoadFailure('model file not found: $modelPath');
    }
    final vae = params.vaePath;
    if (vae != null && !File(vae).existsSync()) {
      throw ImageGenLoadFailure('vae file not found: $vae');
    }
    // One heavy model at a time: refuse if the LLM engine is resident.
    if (isOtherHeavyModelResident?.call() ?? false) {
      throw const ImageGenStateFailure(
        'another model (the LLM) is loaded; unload it before loading an image '
        'model — one heavy model fits in RAM at a time',
      );
    }
    if (_isolate != null) await unload();

    final response = ReceivePort();
    final ready = Completer<_ReadyMsg>();
    final sub = response.listen((dynamic msg) {
      if (!ready.isCompleted) {
        if (msg is _ReadyMsg) {
          ready.complete(msg);
        } else if (msg is _ErrorMsg) {
          ready.completeError(_failureFromKind(msg.kind, msg.message));
        }
        return;
      }
      _handleWorkerMessage(msg);
    });

    try {
      _isolate = await Isolate.spawn<_Bootstrap>(
        _sdWorker,
        _Bootstrap(
          replyPort: response.sendPort,
          libraryPath: libraryPath,
          modelPath: modelPath,
          vaePath: vae,
          threads: params.threads,
        ),
        errorsAreFatal: true,
        debugName: 'dhruva.imagine.worker',
      );
      final r = await ready.future.timeout(
        loadTimeout,
        onTimeout: () => throw ImageGenLoadFailure(
          'model load timed out after ${loadTimeout.inSeconds}s '
          '(worker never signalled ready)',
        ),
      );
      _commandPort = r.commandPort;
      _responsePort = response;
      _responseSub = sub;
      _ctxAddr = r.ctxAddr;
      _cancelFlagAddr = r.cancelFlagAddr;
      _cancelBindings = SdBindings(_openSdLibrary(libraryPath));
    } catch (e) {
      await sub.cancel();
      response.close();
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      throw mapToImageGenFailure(e);
    }
  }

  @override
  Stream<ImageGenEvent> generate(ImageGenParams params) {
    final preflight =
        checkImageGenParams(params) ??
        (!isLoaded
            ? const ImageGenDisposedFailure('no model loaded; call loadModel()')
            : null) ??
        (_activeController != null
            ? const ImageGenStateFailure('a generation is already in flight')
            : null);
    if (preflight != null) return Stream<ImageGenEvent>.error(preflight);

    final id = _nextId++;
    // ignore: close_sinks
    final controller = StreamController<ImageGenEvent>();
    _activeController = controller;
    _activeId = id;

    controller.onListen = () {
      _activeStopwatch = Stopwatch()..start();
      _commandPort?.send(_GenerateCommand(id, params));
    };
    controller.onCancel = () {
      // Consumer unsubscribed → request a cross-thread stop.
      if (_activeId == id) {
        unawaited(cancel());
      }
    };
    return controller.stream;
  }

  void _handleWorkerMessage(dynamic msg) {
    switch (msg) {
      case _ProgressMsg():
        if (msg.id != _activeId) return;
        final c = _activeController;
        if (c != null && !c.isClosed) {
          c.add(ImageGenProgress(step: msg.step, totalSteps: msg.steps));
        }
      case _ResultMsg():
        if (msg.id != _activeId) return;
        final c = _activeController;
        if (c != null && !c.isClosed) {
          c.add(
            ImageGenResult(
              pngBytes: msg.pngBytes,
              width: msg.width,
              height: msg.height,
              elapsedMs: _activeStopwatch?.elapsedMilliseconds ?? 0,
            ),
          );
        }
        _closeActive(msg.id);
      case _CancelledMsg():
        if (msg.id != _activeId) return;
        final c = _activeController;
        if (c != null && !c.isClosed) c.add(const ImageGenCancelled());
        _closeActive(msg.id);
      case _ErrorMsg():
        if (msg.id != _activeId) return;
        final c = _activeController;
        if (c != null && !c.isClosed) {
          c.addError(_failureFromKind(msg.kind, msg.message));
        }
        _closeActive(msg.id);
      case _ShutdownDoneMsg():
        _shutdownCompleter?.complete();
    }
  }

  void _closeActive(int id) {
    if (_activeId != id) return;
    final c = _activeController;
    _activeController = null;
    _activeId = null;
    _activeStopwatch = null;
    if (c != null && !c.isClosed) c.close();
  }

  @override
  Future<void> cancel() async {
    if (_activeId == null) return;
    final ctxAddr = _ctxAddr;
    final flagAddr = _cancelFlagAddr;
    final bindings = _cancelBindings;
    if (ctxAddr == null || flagAddr == null || bindings == null) return;
    // Flip the shared flag first so the worker classifies the resulting
    // `false` return as a cancellation, then signal sd.cpp to stop.
    Pointer<Int32>.fromAddress(flagAddr).value = 1;
    bindings.sd_cancel_generation(
      Pointer<sd_ctx_t>.fromAddress(ctxAddr),
      sd_cancel_mode_t.SD_CANCEL_ALL,
    );
  }

  @override
  Future<void> unload() async {
    // Stop any in-flight generation and let the worker unwind before freeing.
    if (_activeId != null) {
      await cancel();
      // Give the worker a beat to return from generate_image and emit its
      // terminal; the controller is closed by _handleWorkerMessage.
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (_activeId != null && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (_activeId != null) _closeActive(_activeId!);
    }

    final isolate = _isolate;
    final commandPort = _commandPort;
    final response = _responsePort;
    final sub = _responseSub;
    _isolate = null;
    _commandPort = null;
    _responsePort = null;
    _responseSub = null;
    _ctxAddr = null;
    _cancelFlagAddr = null;
    _cancelBindings = null;
    if (isolate == null) return;

    // Ask the worker to free the ctx (free_sd_ctx) and confirm before we drop
    // the isolate — so the multi-GB native free actually happens.
    final done = Completer<void>();
    _shutdownCompleter = done;
    commandPort?.send(_ShutdownCommand(_nextId++));
    try {
      await done.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      // Kill regardless so we never wedge.
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
      throw const ImageGenDisposedFailure('engine has been disposed');
    }
  }
}

// ---------------------------------------------------------------------------
// Isolate protocol
// ---------------------------------------------------------------------------

final class _Bootstrap {
  final SendPort replyPort;
  final String? libraryPath;
  final String modelPath;
  final String? vaePath;
  final int threads;
  const _Bootstrap({
    required this.replyPort,
    required this.libraryPath,
    required this.modelPath,
    required this.vaePath,
    required this.threads,
  });
}

sealed class _Command {
  final int id;
  const _Command(this.id);
}

final class _GenerateCommand extends _Command {
  final ImageGenParams params;
  const _GenerateCommand(super.id, this.params);
}

final class _ShutdownCommand extends _Command {
  const _ShutdownCommand(super.id);
}

final class _ReadyMsg {
  final SendPort commandPort;

  /// Address of the `sd_ctx_t*` (for cross-thread cancel).
  final int ctxAddr;

  /// Address of the shared `int32` cancel-classification flag.
  final int cancelFlagAddr;
  const _ReadyMsg(this.commandPort, this.ctxAddr, this.cancelFlagAddr);
}

final class _ProgressMsg {
  final int id;
  final int step;
  final int steps;
  const _ProgressMsg(this.id, this.step, this.steps);
}

final class _ResultMsg {
  final int id;
  final Uint8List pngBytes;
  final int width;
  final int height;
  const _ResultMsg(this.id, this.pngBytes, this.width, this.height);
}

final class _CancelledMsg {
  final int id;
  const _CancelledMsg(this.id);
}

final class _ErrorMsg {
  final int id;
  final _FailKind kind;
  final String message;
  const _ErrorMsg(this.id, this.kind, this.message);
}

final class _ShutdownDoneMsg {
  const _ShutdownDoneMsg();
}

// ---------------------------------------------------------------------------
// Worker (runs on the spawned generation isolate)
// ---------------------------------------------------------------------------

/// Entry point for the image-gen isolate. Loads the dylib + model here (never
/// on root), sets a progress callback that streams step ticks back, runs
/// `generate_image`, PNG-encodes the result — and frees the ctx on shutdown.
void _sdWorker(_Bootstrap boot) {
  final reply = boot.replyPort;
  final SdBindings bindings;
  try {
    bindings = SdBindings(_openSdLibrary(boot.libraryPath));
  } catch (e) {
    reply.send(_ErrorMsg(0, _FailKind.load, 'failed to load sd library: $e'));
    return;
  }

  // Shared cancel-classification flag (main writes 1 on cancel; we read it to
  // tell a cancelled false-return from a real error). Lives for the ctx's life.
  final cancelFlag = calloc<Int32>();

  // sd.cpp's progress callback is PROCESS-GLOBAL and is invoked during model
  // load too (not just sampling), synchronously on THIS thread — so register it
  // BEFORE new_sd_ctx and NULL it before closing on exit. Otherwise the NEXT
  // isolate's load would reach this (deleted) callback through the stale global
  // pointer and crash ("callback invoked after it has been deleted"). During
  // load currentId is 0, a sentinel the service ignores.
  var currentId = 0;
  final progressCb = NativeCallable<sd_progress_cb_tFunction>.isolateLocal((
    int step,
    int steps,
    double time,
    Pointer<Void> data,
  ) {
    reply.send(_ProgressMsg(currentId, step, steps));
  });
  bindings.sd_set_progress_callback(progressCb.nativeFunction, nullptr);

  void teardownCallbacks() {
    bindings.sd_set_progress_callback(nullptr, nullptr);
    progressCb.close();
    calloc.free(cancelFlag);
  }

  // Build ctx params + load the context.
  final ctxParams = calloc<sd_ctx_params_t>();
  final toFree = <Pointer<NativeType>>[ctxParams];
  Pointer<sd_ctx_t> ctx = nullptr;
  try {
    bindings.sd_ctx_params_init(ctxParams);
    final modelPathC = boot.modelPath.toNativeUtf8();
    toFree.add(modelPathC);
    ctxParams.ref.model_path = modelPathC.cast<Char>();
    if (boot.vaePath != null) {
      final vaeC = boot.vaePath!.toNativeUtf8();
      toFree.add(vaeC);
      ctxParams.ref.vae_path = vaeC.cast<Char>();
    }
    if (boot.threads > 0) ctxParams.ref.n_threads = boot.threads;

    ctx = bindings.new_sd_ctx(ctxParams);
    if (ctx == nullptr) {
      teardownCallbacks();
      reply.send(
        _ErrorMsg(0, _FailKind.load, 'new_sd_ctx returned null (load failed)'),
      );
      return;
    }
    if (!bindings.sd_ctx_supports_image_generation(ctx)) {
      bindings.free_sd_ctx(ctx);
      ctx = nullptr;
      teardownCallbacks();
      reply.send(
        _ErrorMsg(
          0,
          _FailKind.load,
          'model loaded but does not support image generation',
        ),
      );
      return;
    }
  } catch (e, st) {
    if (ctx != nullptr) bindings.free_sd_ctx(ctx);
    ctx = nullptr;
    teardownCallbacks();
    reply.send(_ErrorMsg(0, _classify(e), '$e\n$st'));
    return;
  } finally {
    // sd.cpp copies the ctx params (incl. the path strings) into the context,
    // so the whole scratch buffer is free to release once new_sd_ctx returned.
    for (final p in toFree) {
      calloc.free(p);
    }
    toFree.clear();
  }

  final loadedCtx = ctx;
  final commandRx = ReceivePort();
  final done = Completer<void>();

  reply.send(
    _ReadyMsg(commandRx.sendPort, loadedCtx.address, cancelFlag.address),
  );

  commandRx.listen((dynamic msg) {
    if (msg is _ShutdownCommand) {
      bindings.free_sd_ctx(loadedCtx); // FREE PATH — the multi-GB reclamation.
      teardownCallbacks();
      reply.send(const _ShutdownDoneMsg());
      commandRx.close();
      done.complete();
      return;
    }
    if (msg is _GenerateCommand) {
      currentId = msg.id;
      _runGenerate(msg, bindings, loadedCtx, cancelFlag, reply);
      currentId = 0;
    }
  });

  done.future.whenComplete(() {}); // keep the isolate alive until shutdown.
}

/// Synchronous txt2img: fill the img-gen params, reset the cancel flag, call
/// the blocking `generate_image`, then PNG-encode + free. Runs to completion on
/// the worker; the only way out early is a cross-thread cancel.
void _runGenerate(
  _GenerateCommand cmd,
  SdBindings bindings,
  Pointer<sd_ctx_t> ctx,
  Pointer<Int32> cancelFlag,
  SendPort reply,
) {
  final p = cmd.params;
  final gp = calloc<sd_img_gen_params_t>();
  final promptC = p.prompt.toNativeUtf8();
  final negC = p.negativePrompt.toNativeUtf8();
  final imagesOut = calloc<Pointer<sd_image_t>>();
  final numOut = calloc<Int>();
  try {
    bindings.sd_img_gen_params_init(gp);
    gp.ref.prompt = promptC.cast<Char>();
    gp.ref.negative_prompt = negC.cast<Char>();
    gp.ref.width = p.width;
    gp.ref.height = p.height;
    gp.ref.seed = p.seed;
    gp.ref.batch_count = 1;
    gp.ref.sample_params.sample_steps = p.steps;
    gp.ref.sample_params.guidance.txt_cfg = p.cfgScale;
    gp.ref.sample_params.sample_methodAsInt =
        sample_method_t.EULER_A_SAMPLE_METHOD.value;

    // Clear any stale cancellation from a previous run.
    cancelFlag.value = 0;
    bindings.sd_cancel_generation(ctx, sd_cancel_mode_t.SD_CANCEL_RESET);

    final ok = bindings.generate_image(ctx, gp, imagesOut, numOut);
    if (!ok) {
      if (cancelFlag.value == 1) {
        reply.send(_CancelledMsg(cmd.id));
      } else {
        reply.send(
          _ErrorMsg(
            cmd.id,
            _FailKind.decode,
            'generate_image failed (see sd.cpp log)',
          ),
        );
      }
      return;
    }

    final n = numOut.value;
    final arr = imagesOut.value;
    if (n < 1 || arr == nullptr) {
      reply.send(
        _ErrorMsg(
          cmd.id,
          _FailKind.unknown,
          'generate_image produced 0 images',
        ),
      );
      return;
    }
    final img = arr.ref; // first (and only, batch_count=1) image
    final w = img.width;
    final h = img.height;
    final channels = img.channel;
    final pixelCount = w * h * channels;
    // Copy out of native memory before we free it.
    final pixels = Uint8List.fromList(img.data.asTypedList(pixelCount));
    bindings.free_sd_images(arr, n);

    final png = encodePng(rgb: pixels, width: w, height: h, channels: channels);
    reply.send(_ResultMsg(cmd.id, png, w, h));
  } catch (e, st) {
    reply.send(_ErrorMsg(cmd.id, _classify(e), '$e\n$st'));
  } finally {
    calloc.free(promptC);
    calloc.free(negC);
    calloc.free(imagesOut);
    calloc.free(numOut);
    calloc.free(gp);
  }
}
