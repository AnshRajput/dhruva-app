/// Model detail screen state (T5 §3): license/gated status, the quant file
/// list, and the device RAM reading the verdict chips classify against.
/// `FutureProvider.family` (not a Notifier) — the detail screen has no
/// user-driven mutation of this data itself; `ref.invalidate` covers retry.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/device_info/device_info_service.dart';
import '../../../core/di/providers.dart';
import '../../../data/hf_api/models/model_license_info.dart';
import '../../../data/hf_api/models/quant_variant.dart';

final class ModelDetailData {
  final String repoId;
  final ModelLicenseInfo license;
  final List<QuantVariant> quants;
  final DeviceMemoryInfo memory;

  const ModelDetailData({
    required this.repoId,
    required this.license,
    required this.quants,
    required this.memory,
  });
}

final modelDetailProvider = FutureProvider.family<ModelDetailData, String>((
  ref,
  repoId,
) async {
  final client = ref.watch(hfApiClientProvider);
  final deviceInfo = ref.watch(deviceInfoServiceProvider);

  // License/gated status must be known before any download affordance is
  // shown (Rule: user sees license first) — fetched from the per-repo
  // endpoint, which is authoritative (the search endpoint doesn't carry
  // `gated`).
  final license = await client.getModelLicenseInfo(repoId);
  final files = await client.getRepoFiles(repoId);
  final memory = await deviceInfo.getMemoryInfo();

  return ModelDetailData(
    repoId: repoId,
    license: license,
    quants: client.quantVariantsFrom(files),
    memory: memory,
  );
});
