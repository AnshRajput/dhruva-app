/// "Recommended for your device" rail (Amendment 4c): the verified starter
/// catalog from Loop 0 research (orchestra/TASKS.md / BLACKBOARD.md — repo
/// ids + confirmed Q4_K_M file sizes), hardcoded here as a const list. A
/// catalog service/remote config is YAGNI today — five entries that change
/// on the order of "a new loop's research", not per-release.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/device_info/device_info_service.dart';
import '../../../core/di/providers.dart';

final class StarterModel {
  final String repoId;
  final String displayName;

  /// Confirmed Q4_K_M download size (BLACKBOARD.md "Starter models
  /// confirmed"), used for the rail's size label and tier classification —
  /// same size a `classifyModelTier` call on the detail screen's actual
  /// quant file would use.
  final int approxSizeBytes;

  const StarterModel({
    required this.repoId,
    required this.displayName,
    required this.approxSizeBytes,
  });
}

const starterModelCatalog = <StarterModel>[
  StarterModel(
    repoId: 'bartowski/Llama-3.2-1B-Instruct-GGUF',
    displayName: 'Llama 3.2 1B Instruct',
    approxSizeBytes: 807403520, // ~770 MB
  ),
  StarterModel(
    repoId: 'bartowski/Qwen2.5-1.5B-Instruct-GGUF',
    displayName: 'Qwen2.5 1.5B Instruct',
    approxSizeBytes: 1034027008, // ~986 MB
  ),
  StarterModel(
    repoId: 'bartowski/SmolLM2-1.7B-Instruct-GGUF',
    displayName: 'SmolLM2 1.7B Instruct',
    approxSizeBytes: 1073741824, // ~1 GB
  ),
  StarterModel(
    repoId: 'bartowski/Llama-3.2-3B-Instruct-GGUF',
    displayName: 'Llama 3.2 3B Instruct',
    approxSizeBytes: 2040109466, // ~1.9 GB
  ),
  StarterModel(
    repoId: 'unsloth/Phi-4-mini-instruct-GGUF',
    displayName: 'Phi-4 mini Instruct',
    approxSizeBytes: 2576980378, // ~2.4 GB
  ),
];

/// The device RAM reading the rail's tier chips classify against. Separate
/// from `modelDetailProvider`'s inline read (that one's scoped to a single
/// repo's `FutureProvider.family`) since the rail needs it independent of
/// any specific repo and shared across every card.
final deviceMemoryProvider = FutureProvider<DeviceMemoryInfo>((ref) {
  return ref.watch(deviceInfoServiceProvider).getMemoryInfo();
});
