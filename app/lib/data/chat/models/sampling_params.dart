import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/failures/app_failure.dart';

part 'sampling_params.freezed.dart';

/// llama.cpp sampling knobs for one conversation, persisted as JSON in
/// `Conversations.samplingParamsJson` (see `chat_repository.dart`). Defaults
/// mirror common llama.cpp server/CLI defaults, not this codebase's
/// device-tier defaults — `engine_bindings` clamps `contextLength` against
/// what the loaded model/device can actually support.
///
/// JSON is hand-written (`fromJson`/`toJson` below) rather than
/// `json_serializable`-generated: five scalar fields don't need a second
/// generator in the build, and every other data model in this codebase that
/// round-trips JSON (`data/hf_api/models/`) does the same by hand.
// `fromJson`/`toJson` disabled here — hand-written below — so freezed
// doesn't also wire in json_serializable (which would need a
// `sampling_params.g.dart` part we don't generate; see the class doc).
@Freezed(fromJson: false, toJson: false)
abstract class SamplingParams with _$SamplingParams {
  const factory SamplingParams({
    @Default(0.8) double temperature,
    @Default(0.95) double topP,
    @Default(40) int topK,
    @Default(4096) int contextLength,
    @Default(512) int maxTokens,
    int? seed,
  }) = _SamplingParams;

  const SamplingParams._();

  factory SamplingParams.fromJson(Map<String, dynamic> json) => SamplingParams(
    temperature: (json['temperature'] as num?)?.toDouble() ?? 0.8,
    topP: (json['topP'] as num?)?.toDouble() ?? 0.95,
    topK: (json['topK'] as num?)?.toInt() ?? 40,
    contextLength: (json['contextLength'] as num?)?.toInt() ?? 4096,
    maxTokens: (json['maxTokens'] as num?)?.toInt() ?? 512,
    seed: (json['seed'] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() => {
    'temperature': temperature,
    'topP': topP,
    'topK': topK,
    'contextLength': contextLength,
    'maxTokens': maxTokens,
    if (seed != null) 'seed': seed,
  };

  static const _uint32Max = 4294967295;

  /// Throws [ValidationFailure] if any field is outside its accepted
  /// llama.cpp range. `ChatRepository` calls this before persisting a
  /// `SamplingParams` — a bad value surfaces where the user set it, not
  /// silently clamped three screens later at inference time.
  void validate() {
    if (temperature < 0 || temperature > 2) {
      throw ValidationFailure(
        'temperature must be within 0..2, got $temperature',
      );
    }
    if (topP < 0 || topP > 1) {
      throw ValidationFailure('topP must be within 0..1, got $topP');
    }
    if (topK < 0 || topK > 1000) {
      throw ValidationFailure('topK must be within 0..1000, got $topK');
    }
    if (contextLength < 1 || contextLength > 131072) {
      throw ValidationFailure(
        'contextLength must be within 1..131072, got $contextLength',
      );
    }
    if (maxTokens < 1 || maxTokens > 32768) {
      throw ValidationFailure(
        'maxTokens must be within 1..32768, got $maxTokens',
      );
    }
    if (maxTokens > contextLength) {
      throw ValidationFailure(
        'maxTokens ($maxTokens) cannot exceed contextLength ($contextLength)',
      );
    }
    if (seed != null && (seed! < 0 || seed! > _uint32Max)) {
      throw ValidationFailure('seed must be within 0..$_uint32Max, got $seed');
    }
  }
}
