/// An in-memory [ImageGenService] with no native code, for unit/widget tests
/// and previews. Streams fake per-step progress then a tiny canned PNG, and
/// models the contract that matters: cooperative cancellation, one-in-flight,
/// termination on unload, and typed [ImageGenFailure] surfacing.
library;

import 'dart:async';
import 'dart:typed_data';

import 'image_gen_service.dart';
import 'png_encoder.dart';

final class FakeImageGenService implements ImageGenService {
  /// Delay between progress ticks; also the cooperative-cancel checkpoint.
  final Duration stepDelay;

  /// When set, [loadModel] throws this instead of loading.
  final ImageGenFailure? loadFailure;

  /// When set, [generate]'s stream emits this error instead of an image.
  final ImageGenFailure? generateFailure;

  /// Solid color of the canned image (RGBA), so tests can eyeball/decode it.
  final int r, g, b;

  FakeImageGenService({
    this.stepDelay = const Duration(milliseconds: 5),
    this.loadFailure,
    this.generateFailure,
    this.r = 220,
    this.g = 40,
    this.b = 40,
  });

  bool _loaded = false;
  bool _disposed = false;
  _FakeRun? _run;

  /// Test hooks.
  int loadCount = 0;
  int unloadCount = 0;
  ImageGenParams? lastParams;
  ImageGenLoadParams? lastLoadParams;

  @override
  bool get isLoaded => _loaded && !_disposed;

  @override
  Future<void> loadModel(
    String modelPath, {
    ImageGenLoadParams params = const ImageGenLoadParams(),
  }) async {
    lastLoadParams = params;
    if (_disposed) {
      throw const ImageGenDisposedFailure('engine has been disposed');
    }
    if (loadFailure != null) throw loadFailure!;
    if (_loaded) await unload();
    await Future<void>.delayed(Duration.zero);
    _loaded = true;
    loadCount++;
  }

  /// A tiny (8×8) solid PNG of the configured color — a real, decodable image.
  Uint8List cannedPng({int size = 8}) {
    final px = Uint8List(size * size * 4);
    for (var i = 0; i < size * size; i++) {
      px[i * 4] = r;
      px[i * 4 + 1] = g;
      px[i * 4 + 2] = b;
      px[i * 4 + 3] = 255;
    }
    return encodePng(rgb: px, width: size, height: size, channels: 4);
  }

  @override
  Stream<ImageGenEvent> generate(ImageGenParams params) {
    lastParams = params;
    final preflight =
        checkImageGenParams(params) ??
        (!isLoaded
            ? const ImageGenDisposedFailure('no model loaded; call loadModel()')
            : null) ??
        (_run != null
            ? const ImageGenStateFailure('a generation is already in flight')
            : null);
    if (preflight != null) return Stream<ImageGenEvent>.error(preflight);

    final controller = StreamController<ImageGenEvent>();
    final run = _FakeRun(controller);
    _run = run;

    Future<void> pump() async {
      final sw = Stopwatch()..start();
      try {
        if (generateFailure != null) {
          controller.addError(generateFailure!);
          return;
        }
        for (var step = 1; step <= params.steps; step++) {
          await Future<void>.delayed(stepDelay);
          if (run.cancelled || controller.isClosed) break;
          controller.add(
            ImageGenProgress(step: step, totalSteps: params.steps),
          );
        }
        if (controller.isClosed) return;
        if (run.cancelled) {
          controller.add(const ImageGenCancelled());
        } else {
          controller.add(
            ImageGenResult(
              pngBytes: cannedPng(),
              width: 8,
              height: 8,
              elapsedMs: sw.elapsedMilliseconds,
            ),
          );
        }
      } finally {
        if (!controller.isClosed) await controller.close();
        if (identical(_run, run)) _run = null;
      }
    }

    controller.onListen = () => unawaited(pump());
    controller.onCancel = () => run.cancelled = true;
    return controller.stream;
  }

  @override
  Future<void> cancel() async {
    final run = _run;
    if (run == null) return;
    run.cancelled = true;
    await Future<void>.delayed(stepDelay + const Duration(milliseconds: 2));
  }

  @override
  Future<void> unload() async {
    final run = _run;
    if (run != null) {
      run.cancelled = true;
      if (!run.controller.isClosed) {
        run.controller.add(const ImageGenCancelled());
        await run.controller.close();
      }
      _run = null;
    }
    if (_loaded) unloadCount++;
    _loaded = false;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await unload();
    _disposed = true;
  }
}

class _FakeRun {
  final StreamController<ImageGenEvent> controller;
  bool cancelled = false;
  _FakeRun(this.controller);
}
