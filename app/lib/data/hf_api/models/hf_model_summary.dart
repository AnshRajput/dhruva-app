import 'package:freezed_annotation/freezed_annotation.dart';

import 'model_license_info.dart';

part 'hf_model_summary.freezed.dart';

/// One row from a `/api/models?filter=gguf&search=...` search result.
@freezed
abstract class HfModelSummary with _$HfModelSummary {
  const factory HfModelSummary({
    /// "namespace/model-name".
    required String id,
    required int likes,
    required int downloads,
    required List<String> tags,
    String? pipelineTag,
    required ModelLicenseInfo license,
  }) = _HfModelSummary;
}
