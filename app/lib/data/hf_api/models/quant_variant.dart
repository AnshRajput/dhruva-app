import 'package:freezed_annotation/freezed_annotation.dart';

import 'hf_repo_file.dart';

part 'quant_variant.freezed.dart';

/// A single quantization option for a model, derived from a repo file whose
/// name matched a known GGUF quant token (see `quant_parser.dart`).
@freezed
abstract class QuantVariant with _$QuantVariant {
  const factory QuantVariant({
    /// e.g. "Q4_K_M", "Q8_0", "F16".
    required String label,
    required HfRepoFile file,
  }) = _QuantVariant;
}
