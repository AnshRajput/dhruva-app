/// The one place the battery & heat guard's numbers and decisions live.
library;

import 'device_health.dart';

enum ThermalAction {
  none,

  /// Show the non-blocking "getting hot" banner.
  warn,

  /// Stop the current generation (partial text is kept).
  stop,
}

enum BatteryAdvice {
  none,

  /// Warn (once per session) before starting.
  warn,

  /// Ask the user to confirm before starting.
  confirm,
}

abstract final class DeviceGuardPolicy {
  /// Only polled while a generation is running.
  static const pollInterval = Duration(seconds: 5);

  /// At or below this and not charging: warn before a generation.
  static const batteryWarnPercent = 15;

  /// At or below this and not charging: confirm before a generation.
  static const batteryConfirmPercent = 5;

  static ThermalAction thermalAction(ThermalLevel level) => switch (level) {
    ThermalLevel.serious => ThermalAction.warn,
    ThermalLevel.critical => ThermalAction.stop,
    ThermalLevel.nominal ||
    ThermalLevel.fair ||
    ThermalLevel.unknown => ThermalAction.none,
  };

  /// [alreadyWarned]: the low-battery warning was already shown this session.
  /// An unreadable battery never triggers anything.
  static BatteryAdvice batteryAdvice(
    DeviceHealth health, {
    required bool alreadyWarned,
  }) {
    final level = health.batteryPercent;
    if (level == null || health.isCharging) return BatteryAdvice.none;
    if (level <= batteryConfirmPercent) return BatteryAdvice.confirm;
    if (level <= batteryWarnPercent && !alreadyWarned) {
      return BatteryAdvice.warn;
    }
    return BatteryAdvice.none;
  }
}
