import 'dart:io';

import 'package:dhruva/core/device_health/device_guard_policy.dart';
import 'package:dhruva/core/device_health/device_health.dart';
import 'package:dhruva/core/device_health/device_health_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/device_health_fakes.dart';

DeviceHealth _h(int? pct, {bool charging = false, ThermalLevel? t}) =>
    DeviceHealth(
      batteryPercent: pct,
      isCharging: charging,
      thermal: t ?? ThermalLevel.nominal,
    );

void main() {
  group('policy: thermal', () {
    test('maps every level to an action', () {
      expect(
        {
          for (final l in ThermalLevel.values)
            l: DeviceGuardPolicy.thermalAction(l),
        },
        {
          ThermalLevel.nominal: ThermalAction.none,
          ThermalLevel.fair: ThermalAction.none,
          ThermalLevel.serious: ThermalAction.warn,
          ThermalLevel.critical: ThermalAction.stop,
          ThermalLevel.unknown: ThermalAction.none,
        },
      );
    });
  });

  group('policy: battery', () {
    BatteryAdvice advice(DeviceHealth h, {bool warned = false}) =>
        DeviceGuardPolicy.batteryAdvice(h, alreadyWarned: warned);

    test('healthy or unreadable battery: nothing', () {
      expect(advice(_h(80)), BatteryAdvice.none);
      expect(advice(_h(16)), BatteryAdvice.none);
      expect(advice(_h(null)), BatteryAdvice.none);
      expect(advice(DeviceHealth.unknown), BatteryAdvice.none);
    });

    test('<= 15% and not charging warns, but only once per session', () {
      expect(advice(_h(15)), BatteryAdvice.warn);
      expect(advice(_h(6)), BatteryAdvice.warn);
      expect(advice(_h(15), warned: true), BatteryAdvice.none);
    });

    test('<= 5% and not charging confirms, every time', () {
      expect(advice(_h(5)), BatteryAdvice.confirm);
      expect(advice(_h(0)), BatteryAdvice.confirm);
      expect(advice(_h(5), warned: true), BatteryAdvice.confirm);
    });

    test('charging never warns or confirms', () {
      expect(advice(_h(3, charging: true)), BatteryAdvice.none);
      expect(advice(_h(12, charging: true)), BatteryAdvice.none);
    });
  });

  group('ChannelDeviceHealthService', () {
    const channel = MethodChannel(ChannelDeviceHealthService.channelName);
    TestWidgetsFlutterBinding.ensureInitialized();

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    void mock(Future<Object?> Function(MethodCall) handler) =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, handler);

    test('parses a native reply', () async {
      mock(
        (_) async => {'battery': 42, 'charging': true, 'thermal': 'serious'},
      );
      expect(
        await ChannelDeviceHealthService().read(),
        const DeviceHealth(
          batteryPercent: 42,
          isCharging: true,
          thermal: ThermalLevel.serious,
        ),
      );
    });

    test('-1 battery and unknown thermal become "no reading"', () async {
      mock((_) async => {'battery': -1, 'charging': false, 'thermal': 'wat'});
      expect(await ChannelDeviceHealthService().read(), DeviceHealth.unknown);
    });

    test('missing plugin and platform errors do not throw', () async {
      expect(await ChannelDeviceHealthService().read(), DeviceHealth.unknown);
      mock((_) async => throw PlatformException(code: 'boom'));
      expect(await ChannelDeviceHealthService().read(), DeviceHealth.unknown);
    });
  });

  group('DeviceHealthNotifier poller', () {
    late FakeHealthService service;
    late MemoryGuardStore store;

    /// A container whose guard switch has finished loading (the notifier
    /// reads it synchronously, as it does in the app).
    Future<ProviderContainer> container() async {
      final c = ProviderContainer(
        overrides: [
          deviceHealthServiceProvider.overrideWithValue(service),
          deviceGuardStoreProvider.overrideWith((ref) async => store),
          deviceHealthPollIntervalProvider.overrideWithValue(
            const Duration(milliseconds: 20),
          ),
        ],
      );
      addTearDown(c.dispose);
      c.read(
        deviceHealthProvider,
      ); // builds the notifier, which loads the switch
      await c.read(deviceGuardEnabledProvider.future);
      return c;
    }

    setUp(() {
      service = FakeHealthService(_h(70, t: ThermalLevel.fair));
      store = MemoryGuardStore();
    });

    test('idle: no polling and no reads', () async {
      final c = await container();
      final n = c.read(deviceHealthProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(n.isPolling, isFalse);
      expect(service.reads, 0);
    });

    test('polls while leased, stops when released', () async {
      final c = await container();
      c.listen(deviceHealthProvider, (_, _) {});
      final n = c.read(deviceHealthProvider.notifier);

      expect(n.startPollingIfEnabled(), isTrue);
      expect(n.isPolling, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(service.reads, greaterThanOrEqualTo(3));
      expect(c.read(deviceHealthProvider).thermal, ThermalLevel.fair);

      n.stopPolling();
      expect(n.isPolling, isFalse);
      final after = service.reads;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(service.reads, after);
    });

    test(
      'leases are counted: polling stops only on the last release',
      () async {
        final c = await container();
        final n = c.read(deviceHealthProvider.notifier);
        n.startPollingIfEnabled();
        n.startPollingIfEnabled();
        n.stopPolling();
        expect(n.isPolling, isTrue);
        n.stopPolling();
        expect(n.isPolling, isFalse);
        n.stopPolling(); // extra release is harmless
        expect(n.isPolling, isFalse);
      },
    );

    test(
      'guard switched off: no lease, no polling, no battery advice',
      () async {
        store.enabled = false;
        service.next = _h(3);
        final c = await container();
        final n = c.read(deviceHealthProvider.notifier);
        expect(n.startPollingIfEnabled(), isFalse);
        expect(n.isPolling, isFalse);
        expect(await n.preGenerationAdvice(), BatteryAdvice.none);
        expect(service.reads, 0);
      },
    );

    test(
      'preGenerationAdvice: warn once per session, confirm always',
      () async {
        service.next = _h(12);
        final c = await container();
        final n = c.read(deviceHealthProvider.notifier);
        expect(await n.preGenerationAdvice(), BatteryAdvice.warn);
        expect(await n.preGenerationAdvice(), BatteryAdvice.none);
        service.next = _h(4);
        expect(await n.preGenerationAdvice(), BatteryAdvice.confirm);
        expect(await n.preGenerationAdvice(), BatteryAdvice.confirm);
      },
    );
  });

  group('FileDeviceGuardStore', () {
    test('defaults ON; the off state persists across instances', () async {
      final dir = Directory.systemTemp.createTempSync('guard_store');
      addTearDown(() => dir.deleteSync(recursive: true));
      expect(await FileDeviceGuardStore(dir).isEnabled(), isTrue);
      await FileDeviceGuardStore(dir).setEnabled(false);
      expect(await FileDeviceGuardStore(dir).isEnabled(), isFalse);
      await FileDeviceGuardStore(dir).setEnabled(true);
      expect(await FileDeviceGuardStore(dir).isEnabled(), isTrue);
    });
  });
}
