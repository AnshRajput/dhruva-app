/// Abstract on-device image-generation surface (Loop 8, mirrors
/// `engine_bindings/engine_service.dart`).
///
/// Nothing outside `imagine_engine/` imports the FFI bindings
/// (`sd_bindings.g.dart`) or any `dart:ffi` symbol directly — features and
/// data depend only on this interface and the neutral types below. That keeps
/// the vendored stable-diffusion.cpp choice swappable and the native crash
/// surface contained, exactly like [EngineService] does for llama.cpp.
///
/// Threading: image generation NEVER runs on the root isolate. The concrete
/// [SdImageGenService] owns a dedicated worker isolate that holds the single
/// `sd_ctx_t*` and does all the FFI. See `sd_image_gen_service.dart`.
///
/// Memory: a loaded SD context is a multi-GB resident allocation, so
/// [unload] must fully free it (`free_sd_ctx`), and only ONE heavy model
/// (this OR the LLM engine) may be resident at a time — see the coordination
/// hooks on [SdImageGenService].
library;

import 'dart:typed_data';

/// One event in an image-generation stream.
sealed class ImageGenEvent {
  const ImageGenEvent();
}

/// A diffusion-step progress tick, from sd.cpp's progress callback.
/// [step] is 1-based; [totalSteps] is the requested step budget.
final class ImageGenProgress extends ImageGenEvent {
  final int step;
  final int totalSteps;
  const ImageGenProgress({required this.step, required this.totalSteps});
}

/// Terminal success event: the finished image, PNG-encoded.
final class ImageGenResult extends ImageGenEvent {
  /// A valid, self-contained PNG (RGB or RGBA, 8-bit).
  final Uint8List pngBytes;
  final int width;
  final int height;

  /// Wall-clock milliseconds from generate dispatch to this event.
  final int elapsedMs;
  const ImageGenResult({
    required this.pngBytes,
    required this.width,
    required this.height,
    this.elapsedMs = 0,
  });
}

/// Terminal event when the caller cancelled mid-generation (via [cancel] or
/// by unsubscribing). No image is produced. Distinct from an error so the UI
/// can treat "user stopped" differently from "generation failed".
final class ImageGenCancelled extends ImageGenEvent {
  const ImageGenCancelled();
}

/// Load-time configuration for a Stable Diffusion context. Kept deliberately
/// thin — the underlying `sd_ctx_params_t` has ~40 fields; extend as loops
/// need more knobs.
final class ImageGenLoadParams {
  /// Optional standalone VAE (e.g. an improved `vae-ft-mse` or a taesd).
  /// Null loads the VAE baked into the checkpoint.
  final String? vaePath;

  /// CPU threads for the (CPU-resident) parts of the pipeline. `0` = let
  /// sd.cpp pick (physical core count).
  final int threads;

  const ImageGenLoadParams({this.vaePath, this.threads = 0});
}

/// Sampling configuration for one [ImageGenService.generate] call.
final class ImageGenParams {
  final String prompt;
  final String negativePrompt;
  final int steps;
  final int width;
  final int height;
  final double cfgScale;

  /// RNG seed. `-1` (the default) picks a random seed per call; a fixed
  /// value makes the run reproducible.
  final int seed;

  const ImageGenParams({
    required this.prompt,
    this.negativePrompt = '',
    this.steps = 20,
    this.width = 512,
    this.height = 512,
    this.cfgScale = 7,
    this.seed = -1,
  });
}

/// The image engine's typed failure taxonomy (mirrors `EngineFailure`).
sealed class ImageGenFailure implements Exception {
  final String message;
  final Object? cause;
  const ImageGenFailure(this.message, {this.cause});

  @override
  String toString() => '$runtimeType: $message';
}

/// Model failed to load (bad path, unsupported format, backend init failure).
final class ImageGenLoadFailure extends ImageGenFailure {
  const ImageGenLoadFailure(super.message, {super.cause});
}

/// Out of memory (or below the RAM floor) while loading or generating.
final class ImageGenOutOfMemoryFailure extends ImageGenFailure {
  const ImageGenOutOfMemoryFailure(super.message, {super.cause});
}

/// A generation step failed inside sd.cpp.
final class ImageGenDecodeFailure extends ImageGenFailure {
  const ImageGenDecodeFailure(super.message, {super.cause});
}

/// Bad caller input caught at the service boundary before any native work.
final class ImageGenValidationFailure extends ImageGenFailure {
  const ImageGenValidationFailure(super.message, {super.cause});
}

/// Wrong state for the requested op — e.g. a generation already in flight, or
/// another heavy model (the LLM) is resident so this one can't load (one big
/// model at a time).
final class ImageGenStateFailure extends ImageGenFailure {
  const ImageGenStateFailure(super.message, {super.cause});
}

/// An op was attempted after dispose / with nothing loaded.
final class ImageGenDisposedFailure extends ImageGenFailure {
  const ImageGenDisposedFailure(super.message, {super.cause});
}

/// Last-resort bucket; always carries the original [cause].
final class ImageGenUnknownFailure extends ImageGenFailure {
  const ImageGenUnknownFailure(super.message, {super.cause});
}

/// Validate [ImageGenService.generate] args at the boundary, before any
/// native/isolate work. Returns the failure to surface, or null. Shared by
/// every implementation so the contract can't drift. Returned (not thrown)
/// because generate delivers ALL errors via the stream.
ImageGenFailure? checkImageGenParams(ImageGenParams p) {
  if (p.prompt.trim().isEmpty) {
    return const ImageGenValidationFailure(
      'prompt is empty or whitespace-only',
    );
  }
  if (p.steps < 1) {
    return const ImageGenValidationFailure('steps must be >= 1');
  }
  // SD needs dimensions that are multiples of 64 (the latent/VAE stride).
  if (p.width < 64 ||
      p.height < 64 ||
      p.width % 64 != 0 ||
      p.height % 64 != 0) {
    return const ImageGenValidationFailure(
      'width and height must be multiples of 64 and >= 64',
    );
  }
  return null;
}

/// On-device text-to-image engine. One loaded model at a time. All methods
/// surface [ImageGenFailure] subtypes on error.
abstract interface class ImageGenService {
  /// True between a successful [loadModel] and the next [unload]/[dispose].
  bool get isLoaded;

  /// Load a Stable Diffusion checkpoint (`.safetensors`/`.ckpt`/`.gguf`).
  /// Throws [ImageGenLoadFailure] / [ImageGenOutOfMemoryFailure] on failure,
  /// or [ImageGenStateFailure] if another heavy model is resident (the app
  /// coordinates "one big model at a time" — the LLM must be unloaded first).
  /// Calling [loadModel] while a model is loaded unloads the previous one.
  Future<void> loadModel(String modelPath, {ImageGenLoadParams params});

  /// Generate one image. The returned stream emits [ImageGenProgress] ticks
  /// (one per diffusion step) and then exactly one terminal event:
  /// [ImageGenResult] on success or [ImageGenCancelled] if stopped.
  ///
  /// Single error channel: this NEVER throws synchronously. Every failure —
  /// invalid params, nothing loaded, a generation already in flight, native
  /// decode/OOM — is delivered via the stream's `onError`. Cancelling the
  /// subscription (or calling [cancel]) stops generation.
  Stream<ImageGenEvent> generate(ImageGenParams params);

  /// Cooperatively stop the in-flight [generate], if any (sd.cpp's built-in
  /// `sd_cancel_generation`). The generation stream then terminates with
  /// [ImageGenCancelled].
  Future<void> cancel();

  /// Free the loaded model + context (`free_sd_ctx`). Safe when nothing is
  /// loaded. Multi-GB reclamation — call on background / before loading an LLM.
  Future<void> unload();

  /// Tear the engine down entirely (worker isolate included). Unusable after.
  Future<void> dispose();
}
