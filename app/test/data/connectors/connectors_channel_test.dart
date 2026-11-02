import 'dart:async';

import 'package:dhruva/data/connectors/connector_sources.dart';
import 'package:dhruva/data/connectors/system_sources.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const name = ConnectorsChannel.channelName;
  late MethodChannel mc;
  late ConnectorsChannel channel;
  final calls = <MethodCall>[];
  Object? Function(MethodCall)? handler;

  setUp(() {
    calls.clear();
    handler = null;
    mc = const MethodChannel(name);
    channel = ConnectorsChannel(channel: mc);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mc, (call) async {
          calls.add(call);
          return handler?.call(call);
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mc, null);
  });

  group('permissions', () {
    test('parsePermission maps unknown strings to denied (fail closed)', () {
      expect(
        ConnectorsChannel.parsePermission('granted'),
        DevicePermission.granted,
      );
      expect(
        ConnectorsChannel.parsePermission('notDetermined'),
        DevicePermission.notDetermined,
      );
      for (final other in ['denied', 'permanentlyDenied', '', null, 5]) {
        expect(
          ConnectorsChannel.parsePermission(other),
          DevicePermission.denied,
        );
      }
    });

    test('calendar permission + request go over the channel', () async {
      handler = (c) =>
          c.method == 'calendar.permission' ? 'notDetermined' : 'granted';
      expect(
        await channel.calendarPermission(),
        DevicePermission.notDetermined,
      );
      expect(
        await channel.requestCalendarPermission(),
        DevicePermission.granted,
      );
      expect(calls.map((c) => c.method), [
        'calendar.permission',
        'calendar.request',
      ]);
    });
  });

  group('calendar events', () {
    test(
      'sends epoch millis and parses events, skipping malformed ones',
      () async {
        handler = (_) => [
          {
            'id': 'e1',
            'calendarId': 'c',
            'calendarName': 'Home',
            'title': 'Dentist',
            'description': 'bring card',
            'location': 'Clinic',
            'start': 1000,
            'end': 2000,
            'allDay': false,
            'recurring': true,
            'attendees': [
              {'name': 'Ravi', 'email': 'r@x.com'},
              {'bogus': 1},
              'junk',
            ],
          },
          {'id': 'no-times', 'calendarId': 'c'},
          {'id': '', 'calendarId': 'c', 'start': 1, 'end': 2},
          'not a map',
          {'id': 'bad-start', 'calendarId': 'c', 'start': '1', 'end': 2},
        ];
        final from = DateTime.utc(2026, 11, 1);
        final to = DateTime.utc(2026, 11, 15);
        final events = await channel.calendarEvents(from, to);
        expect(calls.single.arguments, {
          'from': from.millisecondsSinceEpoch,
          'to': to.millisecondsSinceEpoch,
        });
        expect(events, hasLength(1));
        final e = events.single;
        expect(e.title, 'Dentist');
        expect(e.recurring, isTrue);
        expect(e.calendarName, 'Home');
        expect(e.attendees.single.email, 'r@x.com');
        expect(e.start.millisecondsSinceEpoch, 1000);
      },
    );

    test('null list is just empty', () async {
      handler = (_) => null;
      expect(
        await channel.calendarEvents(DateTime.now(), DateTime.now()),
        isEmpty,
      );
    });
  });

  group('folder', () {
    test('pick: a grant, a cancel, and a malformed answer', () async {
      handler = (_) => {'id': 'tree:1', 'name': 'Notes'};
      expect((await channel.pickFolder())!.id, 'tree:1');
      handler = (_) => null;
      expect(await channel.pickFolder(), isNull);
      handler = (_) => {'name': 'no id'};
      expect(await channel.pickFolder(), isNull);
      handler = (_) => {'id': 'tree:2'};
      expect((await channel.pickFolder())!.name, 'Folder');
    });

    test(
      'a folder call that never answers times out instead of hanging',
      () async {
        final slow = ConnectorsChannel(
          channel: mc,
          folderCallTimeout: const Duration(milliseconds: 50),
        );
        handler = (_) => Completer<Object?>().future;
        await expectLater(
          slow.fetchFolderFile('tree:1', 'doc', '/tmp/x.bin', 1024),
          throwsA(isA<FolderFetchException>()),
        );
        await expectLater(
          slow.listFolder('tree:1', 10),
          throwsA(isA<TimeoutException>()),
        );
      },
    );

    test('list passes the cap and drops malformed entries', () async {
      handler = (_) => [
        {'id': 'a', 'name': 'a.txt', 'size': 3, 'modified': 5},
        {'id': 'b', 'name': 'b.txt', 'size': '3', 'modified': 5},
        {'id': '', 'name': 'c.txt', 'size': 3, 'modified': 5},
        {'name': 'd.txt', 'size': 3, 'modified': 5},
        7,
      ];
      final out = await channel.listFolder('tree:1', 2000);
      expect(calls.single.arguments, {'id': 'tree:1', 'maxFiles': 2000});
      expect(out.map((e) => e.id), ['a']);
    });

    test(
      'fetch sends dest + cap; a native refusal becomes FolderFetchException',
      () async {
        handler = (_) => null;
        await channel.fetchFolderFile('tree:1', 'doc', '/tmp/x.bin', 1024);
        expect(calls.single.arguments, {
          'id': 'tree:1',
          'entryId': 'doc',
          'dest': '/tmp/x.bin',
          'maxBytes': 1024,
        });
        handler = (_) => throw PlatformException(
          code: 'outside_grant',
          message: 'Not inside the granted folder',
        );
        await expectLater(
          channel.fetchFolderFile('tree:1', '../x', '/tmp/x.bin', 1024),
          throwsA(
            isA<FolderFetchException>().having(
              (e) => e.message,
              'message',
              contains('granted folder'),
            ),
          ),
        );
      },
    );

    test('SystemFolderSource: an unreachable/erroring grant reads as not '
        'reachable', () async {
      final source = SystemFolderSource(channel);
      handler = (_) => true;
      expect(await source.isReachable('g'), isTrue);
      handler = (_) => throw PlatformException(code: 'gone');
      expect(await source.isReachable('g'), isFalse);
      handler = (_) => null;
      expect(await source.isReachable('g'), isFalse);
    });
  });

  group('notifications + power', () {
    test('calls and defaults', () async {
      handler = (c) => switch (c.method) {
        'notifications.granted' => true,
        'notifications.queueDir' => '/data/q',
        'power.charging' => true,
        _ => null,
      };
      expect(await channel.notificationAccessGranted(), isTrue);
      expect(await channel.notificationQueueDirectory(), '/data/q');
      await channel.setNotificationCapture(true);
      await channel.setExcludedPackages(['com.a.b']);
      await channel.openNotificationSettings();
      expect(await channel.isCharging(), isTrue);
      expect(calls.map((c) => c.method), [
        'notifications.granted',
        'notifications.queueDir',
        'notifications.capture',
        'notifications.excluded',
        'notifications.settings',
        'power.charging',
      ]);
      expect(calls[2].arguments, {'enabled': true});
      expect(calls[3].arguments, {
        'packages': ['com.a.b'],
      });
    });

    test('null answers fail closed', () async {
      handler = (_) => null;
      expect(await channel.notificationAccessGranted(), isFalse);
      expect(await channel.isCharging(), isFalse);
    });

    test('the charging probe never throws', () async {
      handler = (_) => throw PlatformException(code: 'x');
      expect(await chargingProbe(channel)(), isFalse);
    });

    test('access check swallows a platform error as "not granted"', () async {
      final access = SystemNotificationAccess(channel);
      handler = (_) => throw PlatformException(code: 'x');
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(access.supported, isTrue);
      expect(await access.isGranted(), isFalse);
    });

    test('iOS: unsupported and never asks the platform', () async {
      final access = SystemNotificationAccess(channel);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(access.supported, isFalse);
      expect(await access.isGranted(), isFalse);
      expect(calls, isEmpty);
    });
  });

  test('Android calendar goes through our channel (READ_CALENDAR only), '
      'not the plugin', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    handler = (c) => c.method == 'calendar.events' ? <Object?>[] : 'granted';
    final source = SystemCalendarSource(channel);
    expect(await source.permission(), DevicePermission.granted);
    expect(await source.request(), DevicePermission.granted);
    expect(await source.events(DateTime.now(), DateTime.now()), isEmpty);
    await source.openSettings();
    expect(calls.map((c) => c.method), [
      'calendar.permission',
      'permission.markAsked',
      'calendar.request',
      'calendar.events',
      'app.settings',
    ]);
  });
}
