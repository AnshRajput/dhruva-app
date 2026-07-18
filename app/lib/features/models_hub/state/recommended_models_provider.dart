/// models_hub's device-RAM provider for the curated cards' verdict chips.
///
/// The curated catalog itself (`StarterModel`, `starterModelCatalog`,
/// `recommendedStarterModel`) moved to `data/models/starter_catalog.dart`
/// when `features/onboarding` (WS2) needed it too — a feature can't import
/// another feature (ADR-002), so the shared data moved DOWN to `data/`. It's
/// re-exported here so every existing `recommended_models_provider.dart`
/// importer (curated tab/card, models-hub screen, their tests) is untouched.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/device_info/device_info_service.dart';
import '../../../core/di/providers.dart';

export '../../../data/models/starter_catalog.dart';

/// The device RAM reading the curated cards' tier chips classify against.
/// Shared across every card (independent of any specific repo, unlike
/// `modelDetailProvider`'s per-repo inline read).
final deviceMemoryProvider = FutureProvider<DeviceMemoryInfo>((ref) {
  return ref.watch(deviceInfoServiceProvider).getMemoryInfo();
});
