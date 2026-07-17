import 'package:freezed_annotation/freezed_annotation.dart';

part 'model_license_info.freezed.dart';

/// Whether a repo requires HF authentication/approval before its files can
/// be downloaded. Mirrors the HF API's `gated` field, which is `false`,
/// `"manual"`, or `"auto"` (see orchestra/research/hf-api.md §4).
enum HfGatedStatus {
  /// `gated: false` — no login/approval needed.
  none,

  /// `gated: "manual"` — repo owner must approve each request.
  manual,

  /// `gated: "auto"` — automatic approval once the user accepts terms.
  auto,
}

/// License + gating status for a repo, from `/api/models/{repo}`.
@freezed
abstract class ModelLicenseInfo with _$ModelLicenseInfo {
  const factory ModelLicenseInfo({
    /// `cardData.license` (falls back to the `license:*` tag) e.g.
    /// "apache-2.0", "llama2". Null when the repo declares none.
    String? license,
    required HfGatedStatus gatedStatus,
  }) = _ModelLicenseInfo;

  const ModelLicenseInfo._();

  /// True when the user needs to authenticate with HF before this repo's
  /// files are downloadable — the UI's "requires login" gate.
  bool get requiresAuth => gatedStatus != HfGatedStatus.none;
}
