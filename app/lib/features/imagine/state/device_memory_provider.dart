/// The device RAM reading Imagine's RAM gate classifies against. A tiny
/// duplicate of models_hub's own `deviceMemoryProvider` (same one-line body
/// over `DeviceInfoService.getMemoryInfo()`) rather than an import — ADR-002
/// bans `features/imagine` reaching into `features/models_hub`, and this is
/// three lines, not worth promoting to `core/` for two callers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/device_info/device_info_service.dart';
import '../../../core/di/providers.dart';

final imagineDeviceMemoryProvider = FutureProvider<DeviceMemoryInfo>((ref) {
  return ref.watch(deviceInfoServiceProvider).getMemoryInfo();
});
