import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';

import 'model_tier.dart' show nominalRamBytes;

/// Total + available RAM, in bytes. `availableBytes` is a point-in-time
/// reading (the OS reclaims/allocates continuously) — only `totalBytes` is
/// used for [ModelTier] classification; `availableBytes` is informational.
final class DeviceMemoryInfo {
  final int totalBytes;
  final int availableBytes;
  const DeviceMemoryInfo({
    required this.totalBytes,
    required this.availableBytes,
  });
}

/// Total + free disk space on the volume the app's document directory lives
/// on, in bytes.
final class DeviceStorageInfo {
  final int totalBytes;
  final int freeBytes;
  const DeviceStorageInfo({required this.totalBytes, required this.freeBytes});
}

/// Platform RAM/storage lookups, behind an interface so `model_tier.dart`'s
/// pure classification logic can be unit-tested against a fake (ADR-002
/// testing pyramid) without touching real platform channels.
abstract interface class DeviceInfoService {
  Future<DeviceMemoryInfo> getMemoryInfo();
  Future<DeviceStorageInfo> getStorageInfo();
}

/// `device_info_plus`-backed implementation. Verified against the plugin's
/// own source (13.2.0): `AndroidDeviceInfo`/`IosDeviceInfo` both expose
/// `physicalRamSize`/`availableRamSize` (megabytes, via ActivityManager on
/// Android / NSProcessInfo.physicalMemory on iOS) and `freeDiskSize`/
/// `totalDiskSize` (bytes) — no custom MethodChannel needed on either
/// platform.
final class PluginDeviceInfoService implements DeviceInfoService {
  final DeviceInfoPlugin _plugin;
  PluginDeviceInfoService({DeviceInfoPlugin? plugin})
    : _plugin = plugin ?? DeviceInfoPlugin();

  static const _bytesPerMb = 1024 * 1024;

  @override
  Future<DeviceMemoryInfo> getMemoryInfo() async {
    // `totalBytes` is rounded up to the marketed capacity via
    // [nominalRamBytes]: ActivityManager/NSProcessInfo under-report physical
    // RAM by the kernel + reserved carve-outs, and model_tier's floors are
    // written against marketed capacity. `availableBytes` stays raw — it's an
    // informational live reading, not tiered against a floor.
    if (Platform.isAndroid) {
      final info = await _plugin.androidInfo;
      return DeviceMemoryInfo(
        totalBytes: nominalRamBytes(info.physicalRamSize * _bytesPerMb),
        availableBytes: info.availableRamSize * _bytesPerMb,
      );
    }
    final info = await _plugin.iosInfo;
    return DeviceMemoryInfo(
      totalBytes: nominalRamBytes(info.physicalRamSize * _bytesPerMb),
      availableBytes: info.availableRamSize * _bytesPerMb,
    );
  }

  @override
  Future<DeviceStorageInfo> getStorageInfo() async {
    if (Platform.isAndroid) {
      final info = await _plugin.androidInfo;
      return DeviceStorageInfo(
        totalBytes: info.totalDiskSize,
        freeBytes: info.freeDiskSize,
      );
    }
    final info = await _plugin.iosInfo;
    return DeviceStorageInfo(
      totalBytes: info.totalDiskSize,
      freeBytes: info.freeDiskSize,
    );
  }
}

/// Fixed reading, for tests and previews.
final class FakeDeviceInfoService implements DeviceInfoService {
  final DeviceMemoryInfo memory;
  final DeviceStorageInfo storage;
  const FakeDeviceInfoService({required this.memory, required this.storage});

  @override
  Future<DeviceMemoryInfo> getMemoryInfo() async => memory;

  @override
  Future<DeviceStorageInfo> getStorageInfo() async => storage;
}
