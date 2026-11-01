import 'package:dhruva/core/device_health/device_health.dart';
import 'package:dhruva/core/device_health/device_health_provider.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

class FakeHealthService implements DeviceHealthService {
  DeviceHealth next;
  int reads = 0;
  FakeHealthService([this.next = DeviceHealth.unknown]);

  @override
  Future<DeviceHealth> read() async {
    reads++;
    return next;
  }
}

class MemoryGuardStore implements DeviceGuardStore {
  bool enabled;
  MemoryGuardStore({this.enabled = true});

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> setEnabled(bool v) async => enabled = v;
}

/// Keeps tests off the native channel and the disk-backed switch store
/// (same idea as overriding the engine and device-info providers).
List<Override> deviceHealthTestOverrides() => [
  deviceHealthServiceProvider.overrideWithValue(FakeHealthService()),
  deviceGuardStoreProvider.overrideWith((ref) async => MemoryGuardStore()),
];
