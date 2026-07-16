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
final class ChatTurn {
  final EngineRole role;
  final String content;
  const ChatTurn(this.role, this.content);
  const ChatTurn.system(this.content) : role = EngineRole.system;
  const ChatTurn.user(this.content) : role = EngineRole.user;
  const ChatTurn.assistant(this.content) : role = EngineRole.assistant;
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
  const EngineCompletion({required this.reason, required this.tokenCount});
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

  const EngineLoadParams({
    this.contextSize = 4096,
    this.gpuLayers = 99,
    this.batchSize = 512,
  });
}

/// Sampling configuration for a single [EngineService.generate] call.
final class EngineGenerateParams {
  final int maxTokens;
  final double temperature;
  final int topK;
  final double topP;

  /// Deterministic argmax sampling; overrides temperature/top-k/top-p.
  final bool greedy;

  const EngineGenerateParams({
    this.maxTokens = 256,
    this.temperature = 0.7,
    this.topK = 40,
    this.topP = 0.95,
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
/// before any native/isolate work. Throws the right [EngineFailure] subtype.
/// Shared by every [EngineService] implementation so the contract can't drift.
void checkGenerateArgs(String? prompt, List<ChatTurn>? messages) {
  if ((prompt == null) == (messages == null)) {
    throw const EngineUnknownFailure(
      'generate requires exactly one of prompt or messages',
    );
  }
  if (prompt != null && prompt.trim().isEmpty) {
    throw const EngineValidationFailure('prompt is empty or whitespace-only');
  }
  if (messages != null && messages.isEmpty) {
    throw const EngineValidationFailure('messages is empty');
  }
}

/// On-device inference engine. One loaded model at a time (ADR-001: single
/// active session). All methods throw [EngineFailure] subtypes on error.
abstract interface class EngineService {
  /// True between a successful [load] and the next [unload]/[dispose].
  bool get isLoaded;

  /// Load a GGUF model + context. Throws [EngineLoadFailure] /
  /// [EngineOutOfMemoryFailure] on failure. Calling [load] while a model is
  /// loaded unloads the previous one first (one native context per model).
  Future<void> load(String modelPath, {EngineLoadParams params});

  /// Stream a completion. Provide exactly one of [prompt] or [messages].
  /// The returned stream ends with an [EngineCompletion]. Cancelling the
  /// subscription (or calling [cancel]) stops generation cooperatively
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
