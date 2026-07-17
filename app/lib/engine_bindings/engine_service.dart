/// Abstract inference-engine surface (ADR-001 / ADR-002).
///
/// Nothing outside `engine_bindings/` imports `llama_cpp_dart` or any FFI
/// symbol directly — features and data depend only on this interface and the
/// neutral types below. That keeps the ADR-001 engine choice swappable and
/// the native crash surface contained.
///
/// Threading (ADR-001): inference never runs on the root isolate. The
/// concrete [EngineService] delegates to `llama_cpp_dart`'s own worker
/// isolate, which owns the native model/context and streams tokens back over
/// a `SendPort`. See `llama_engine_service.dart` for the source citation — we
/// deliberately do NOT wrap that in a second isolate.
library;

import 'dart:typed_data';

/// Where generation stopped.
enum EngineStopReason {
  /// The model emitted an end-of-generation token.
  endOfSequence,

  /// The `maxTokens` budget was hit.
  maxTokens,

  /// The caller cancelled mid-stream.
  cancelled,
}

/// Role of a chat turn passed to [EngineService.generate].
enum EngineRole { system, user, assistant }

/// One turn in a chat prompt.
///
/// [images] carries encoded image bytes (PNG/JPEG/… — mtmd auto-detects the
/// format) attached to this turn. Only meaningful on a `user` turn fed to a
/// multimodal model (see [EngineService.isMultimodal]); the engine prepends
/// one media marker per image to the rendered prompt. Empty for text turns.
final class ChatTurn {
  final EngineRole role;
  final String content;
  final List<Uint8List> images;
  const ChatTurn(this.role, this.content, {this.images = const []});
  const ChatTurn.system(this.content)
    : role = EngineRole.system,
      images = const [];
  const ChatTurn.user(this.content, {this.images = const []})
    : role = EngineRole.user;
  const ChatTurn.assistant(this.content)
    : role = EngineRole.assistant,
      images = const [];
}

/// One event in a generation stream.
sealed class EngineEvent {
  const EngineEvent();
}

/// A decoded text delta. [text] may be empty for sub-codepoint fragments that
/// the streaming UTF-8 accumulator is still buffering.
final class EngineToken extends EngineEvent {
  final int tokenId;
  final String text;
  const EngineToken({required this.tokenId, required this.text});
}

/// Terminal event of a generation stream.
final class EngineCompletion extends EngineEvent {
  final EngineStopReason reason;

  /// Number of tokens generated in this run.
  final int tokenCount;

  /// Wall-clock milliseconds spanning command dispatch → this terminal event,
  /// measured on the calling isolate (prompt prefill included). Authoritative
  /// final stat for a tok/s readout: `tokenCount / (elapsedMs / 1000)`.
  ///
  /// For a *live* meter during streaming, the consumer times [EngineToken]
  /// arrivals on its own isolate (the worker→main hop is ~constant, so
  /// inter-arrival deltas track generation rate) — no per-token timestamp is
  /// shipped because arrival time is already available where the meter lives.
  final int elapsedMs;
  const EngineCompletion({
    required this.reason,
    required this.tokenCount,
    this.elapsedMs = 0,
  });
}

/// Model + context load configuration. A thin, engine-neutral subset of the
/// underlying params; extend as loops need more knobs.
final class EngineLoadParams {
  /// Context window in tokens.
  final int contextSize;

  /// Layers offloaded to the GPU/NPU backend. `0` = CPU only. Negative = all.
  final int gpuLayers;

  /// Prompt-prefill batch size.
  final int batchSize;

  /// Max concurrent sequences the context hosts (ADR-001 is single-session, so
  /// the default is 1; the Model Arena loop raises it). The native limit is
  /// 256 — higher values fail fast at context creation.
  final int maxSequences;

  /// Absolute path to the multimodal projector (`mmproj-*.gguf`) that pairs
  /// with a vision model. When set, the model loads in multimodal mode and
  /// [EngineService.isMultimodal] becomes true; [generate] can then accept
  /// image input on a [ChatTurn]. When null the model loads text-only.
  ///
  /// A path that doesn't exist or fails to initialise raises a typed
  /// [EngineLoadFailure] ("vision projector …"). Loading a vision GGUF
  /// *without* this projector is allowed — it simply runs text-only
  /// (`isMultimodal == false`), since the engine can't decode images without
  /// a projector to point at.
  final String? mmprojPath;

  const EngineLoadParams({
    this.contextSize = 4096,
    this.gpuLayers = 99,
    this.batchSize = 512,
    this.maxSequences = 1,
    this.mmprojPath,
  });
}

/// Sampling configuration for a single [EngineService.generate] call.
final class EngineGenerateParams {
  final int maxTokens;
  final double temperature;
  final int topK;
  final double topP;

  /// RNG seed for stochastic sampling. `0xFFFFFFFF` (the default) means the
  /// runtime picks a random seed per call; a fixed value makes a
  /// temperature>0 run reproducible. Ignored when [greedy] is set.
  ///
  /// Support matrix (what reaches the native sampler at pinned commit
  /// c6e3778): temperature, topK, topP, seed, greedy — all wired here. The
  /// package's `SamplerParams` also carries minP, typicalP, repeat/frequency/
  /// presence penalties, Mirostat, dynamic-temp, XTC, DRY, adaptive-P,
  /// grammar and logit-bias; those are deliberately NOT surfaced yet (chat's
  /// sampling sheet doesn't set them). Add fields here + plumb in
  /// `llama_engine_service` when a loop needs them — purely additive.
  final int seed;

  /// Deterministic argmax sampling; overrides temperature/top-k/top-p/seed.
  final bool greedy;

  const EngineGenerateParams({
    this.maxTokens = 256,
    this.temperature = 0.7,
    this.topK = 40,
    this.topP = 0.95,
    this.seed = 0xFFFFFFFF,
    this.greedy = false,
  });
}

/// The engine's typed failure taxonomy (the `EngineFailure` branch of the
/// ADR-002 sealed error tree). Repositories map lower-layer errors into this;
/// UI maps it to a user message + recovery affordance.
sealed class EngineFailure implements Exception {
  final String message;
  final Object? cause;
  const EngineFailure(this.message, {this.cause});

  @override
  String toString() => '$runtimeType: $message';
}

/// Model or context failed to load (bad path, unsupported format, native
/// library/backend init failure).
final class EngineLoadFailure extends EngineFailure {
  const EngineLoadFailure(super.message, {super.cause});
}

/// Out of memory while loading or decoding.
final class EngineOutOfMemoryFailure extends EngineFailure {
  const EngineOutOfMemoryFailure(super.message, {super.cause});
}

/// A decode step failed at runtime (e.g. KV cache overflow with shift off).
final class EngineDecodeFailure extends EngineFailure {
  const EngineDecodeFailure(super.message, {super.cause});
}

/// Bad caller input caught at the service boundary before any native work
/// (the `ValidationFailure` branch of the ADR-002 taxonomy, engine-scoped).
final class EngineValidationFailure extends EngineFailure {
  const EngineValidationFailure(super.message, {super.cause});
}

/// The engine is in the wrong state for the requested op (e.g. a generation
/// is already in flight — one active session per ADR-001). A usage error,
/// distinct from bad input ([EngineValidationFailure]).
final class EngineStateFailure extends EngineFailure {
  const EngineStateFailure(super.message, {super.cause});
}

/// An operation was attempted after the engine (or a required model) was
/// disposed / not loaded.
final class EngineDisposedFailure extends EngineFailure {
  const EngineDisposedFailure(super.message, {super.cause});
}

/// Last-resort bucket. Always carries the original [cause].
final class EngineUnknownFailure extends EngineFailure {
  const EngineUnknownFailure(super.message, {super.cause});
}

/// Validate [EngineService.generate] arguments at the service boundary,
/// before any native/isolate work. Returns the failure to surface, or null if
/// the args are valid. Shared by every implementation so the contract can't
/// drift. Returned (not thrown) because generate delivers ALL errors via the
/// stream — see [EngineService.generate].
EngineFailure? checkGenerateArgs(String? prompt, List<ChatTurn>? messages) {
  if ((prompt == null) == (messages == null)) {
    return const EngineValidationFailure(
      'generate requires exactly one of prompt or messages',
    );
  }
  if (prompt != null && prompt.trim().isEmpty) {
    return const EngineValidationFailure('prompt is empty or whitespace-only');
  }
  if (messages != null && messages.isEmpty) {
    return const EngineValidationFailure('messages is empty');
  }
  return null;
}

/// On-device inference engine. One loaded model at a time (ADR-001: single
/// active session). All methods throw [EngineFailure] subtypes on error.
abstract interface class EngineService {
  /// True between a successful [load] and the next [unload]/[dispose].
  bool get isLoaded;

  /// True when the currently-loaded model has a multimodal projector attached
  /// (an [EngineLoadParams.mmprojPath] that initialised and supports vision),
  /// so [generate] can accept image input on a [ChatTurn]. False when nothing
  /// is loaded or the model is text-only. Drives the UI attach-image gate.
  bool get isMultimodal;

  /// Load a GGUF model + context. Throws [EngineLoadFailure] /
  /// [EngineOutOfMemoryFailure] on failure. Calling [load] while a model is
  /// loaded unloads the previous one first (one native context per model).
  Future<void> load(String modelPath, {EngineLoadParams params});

  /// Stream a completion. Provide exactly one of [prompt] or [messages].
  ///
  /// Single error channel: this NEVER throws synchronously. Every failure —
  /// invalid arguments ([EngineValidationFailure]), no model loaded
  /// ([EngineDisposedFailure]), a generation already in flight
  /// ([EngineStateFailure]), and mid-stream decode/OOM failures — is delivered
  /// via the returned stream's `onError`, so consumers handle exactly one
  /// path. On success the stream ends with an [EngineCompletion]. Cancelling
  /// the subscription (or calling [cancel]) stops generation cooperatively
  /// between tokens.
  Stream<EngineEvent> generate({
    String? prompt,
    List<ChatTurn>? messages,
    EngineGenerateParams params,
  });

  /// Cooperatively stop the in-flight [generate], if any. Resolves once the
  /// stop has been requested; the generation stream terminates with an
  /// [EngineCompletion] whose reason is [EngineStopReason.cancelled].
  Future<void> cancel();

  /// Free the loaded model + context. Safe to call when nothing is loaded.
  /// After this, [isLoaded] is false and [generate] throws until [load].
  Future<void> unload();

  /// Tear the engine down entirely (worker isolate included). The instance is
  /// unusable afterwards.
  Future<void> dispose();
}
