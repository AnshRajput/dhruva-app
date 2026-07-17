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

    /// The best-matched mmproj projector for [file] (see
    /// `vision_pairing.dart`'s `matchMmprojFor`), or null when this repo has
    /// no mmproj files at all (a text-only model). Non-null marks [file] as
    /// vision-capable — see [isVision].
    HfRepoFile? mmprojFile,
  }) = _QuantVariant;

  const QuantVariant._();

  /// True when [file] is a vision-capable GGUF — this repo has a paired
  /// mmproj projector for it.
  bool get isVision => mmprojFile != null;
}
