/// Riverpod side of the battery & heat guard: the polled [DeviceHealth], the
/// persisted on/off switch, and the pre-generation battery check.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'device_guard_policy.dart';
import 'device_health.dart';

final deviceHealthServiceProvider = Provider<DeviceHealthService>(
  (ref) => ChannelDeviceHealthService(),
);

/// Overridable so tests don't wait 5 s.
final deviceHealthPollIntervalProvider = Provider<Duration>(
  (ref) => DeviceGuardPolicy.pollInterval,
);

/// "Battery & heat guard" switch store. Default ON, so the sentinel file marks
/// the OFF state (same sentinel-file approach as the onboarding flag: no new
/// dependency, no Drift migration).
abstract interface class DeviceGuardStore {
  Future<bool> isEnabled();
  Future<void> setEnabled(bool enabled);
}

final class FileDeviceGuardStore implements DeviceGuardStore {
  FileDeviceGuardStore(this.directory);

  final Directory directory;

  File get _offFlag => File(p.join(directory.path, '.device_guard_off'));

  @override
  Future<bool> isEnabled() async => !_offFlag.existsSync();

  @override
  Future<void> setEnabled(bool enabled) async {
    if (enabled) {
      if (_offFlag.existsSync()) _offFlag.deleteSync();
    } else if (!_offFlag.existsSync()) {
      _offFlag.createSync(recursive: true);
    }
  }
}

final deviceGuardStoreProvider = FutureProvider<DeviceGuardStore>((ref) async {
  return FileDeviceGuardStore(await getApplicationSupportDirectory());
});

class DeviceGuardEnabledNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final store = await ref.watch(deviceGuardStoreProvider.future);
    return store.isEnabled();
  }

  Future<void> set(bool enabled) async {
    final store = await ref.read(deviceGuardStoreProvider.future);
    state = AsyncData(enabled);
    await store.setEnabled(enabled);
  }
}

final deviceGuardEnabledProvider =
    AsyncNotifierProvider<DeviceGuardEnabledNotifier, bool>(
      DeviceGuardEnabledNotifier.new,
    );

/// Latest reading. Polls only while at least one generation holds a lease.
class DeviceHealthNotifier extends Notifier<DeviceHealth> {
  Timer? _timer;
  int _leases = 0;
  bool _lowBatteryWarned = false;

  @override
  DeviceHealth build() {
    ref.onDispose(() => _timer?.cancel());
    // Keep the switch loaded, so the checks below can read it synchronously
    // and never wait on disk before a generation.
    ref.listen(deviceGuardEnabledProvider, (_, _) {});
    return DeviceHealth.unknown;
  }

  bool get isPolling => _timer != null;

  /// Not yet loaded, or failed to load: the default is ON.
  bool get _guardOn => ref.read(deviceGuardEnabledProvider).value ?? true;

  Future<DeviceHealth> refresh() async {
    final health = await ref.read(deviceHealthServiceProvider).read();
    if (ref.mounted) state = health;
    return health;
  }

  /// Takes a polling lease when the guard is on. Returns whether one was
  /// taken; the caller must then pair it with [stopPolling].
  bool startPollingIfEnabled() {
    if (!_guardOn) return false;
    if (_leases++ == 0) {
      // Forget the last generation's heat reading: only a fresh one may stop
      // this reply (and a fresh "critical" always differs from "unknown", so
      // listeners always hear it).
      state = DeviceHealth(
        batteryPercent: state.batteryPercent,
        isCharging: state.isCharging,
      );
      unawaited(refresh());
      _timer = Timer.periodic(
        ref.read(deviceHealthPollIntervalProvider),
        (_) => unawaited(refresh()),
      );
    }
    return true;
  }

  void stopPolling() {
    if (_leases == 0) return;
    if (--_leases == 0) {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Fresh battery check before a generation starts. A warning is reported
  /// once per session; a confirm-level check is reported every time.
  Future<BatteryAdvice> preGenerationAdvice() async {
    if (!_guardOn) return BatteryAdvice.none;
    final advice = DeviceGuardPolicy.batteryAdvice(
      await refresh(),
      alreadyWarned: _lowBatteryWarned,
    );
    if (advice == BatteryAdvice.warn) _lowBatteryWarned = true;
    return advice;
  }
}

final deviceHealthProvider =
    NotifierProvider<DeviceHealthNotifier, DeviceHealth>(
      DeviceHealthNotifier.new,
    );
