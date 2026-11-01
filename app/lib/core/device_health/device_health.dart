/// Battery + thermal readings from the OS, over a tiny platform channel
/// (`app.dhruva/device_health`, no pub dependency). Native side:
/// `MainActivity.kt` (BatteryManager sticky intent + PowerManager thermal
/// status, API 29+) and `AppDelegate.swift` (UIDevice battery +
/// ProcessInfo.thermalState). Both return `{battery: int, charging: bool,
/// thermal: String}`; anything unavailable (simulator, API < 29) comes back
/// as -1 / "unknown", never as an exception.
library;

import 'package:flutter/services.dart';

enum ThermalLevel {
  nominal,
  fair,
  serious,
  critical,
  unknown;

  static ThermalLevel parse(Object? raw) => ThermalLevel.values.firstWhere(
    (l) => l.name == raw,
    orElse: () => ThermalLevel.unknown,
  );
}

final class DeviceHealth {
  /// 0-100, or null when the OS can't say.
  final int? batteryPercent;
  final bool isCharging;
  final ThermalLevel thermal;

  const DeviceHealth({
    this.batteryPercent,
    this.isCharging = false,
    this.thermal = ThermalLevel.unknown,
  });

  static const unknown = DeviceHealth();

  @override
  bool operator ==(Object other) =>
      other is DeviceHealth &&
      other.batteryPercent == batteryPercent &&
      other.isCharging == isCharging &&
      other.thermal == thermal;

  @override
  int get hashCode => Object.hash(batteryPercent, isCharging, thermal);

  @override
  String toString() =>
      'DeviceHealth($batteryPercent%, charging: $isCharging, $thermal)';
}

abstract interface class DeviceHealthService {
  /// Never throws: failures map to [DeviceHealth.unknown].
  Future<DeviceHealth> read();
}

final class ChannelDeviceHealthService implements DeviceHealthService {
  static const channelName = 'app.dhruva/device_health';

  ChannelDeviceHealthService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  final MethodChannel _channel;

  @override
  Future<DeviceHealth> read() async {
    try {
      final map = await _channel.invokeMapMethod<String, Object?>('read');
      if (map == null) return DeviceHealth.unknown;
      final battery = map['battery'];
      return DeviceHealth(
        batteryPercent: battery is int && battery >= 0 && battery <= 100
            ? battery
            : null,
        isCharging: map['charging'] == true,
        thermal: ThermalLevel.parse(map['thermal']),
      );
    } catch (_) {
      // PlatformException, MissingPluginException (tests, desktop), or no
      // binding yet: a failed read is "no reading", never a crash.
      return DeviceHealth.unknown;
    }
  }
}
