// Calendar and Contacts decide "the system can ask again" vs "blocked" through
// one PermissionGate, from platform truth (asked flag + Android's
// shouldShowRequestPermissionRationale), not from the plugin enum. The fakes
// here model what the real plugins and Android do:
//  * flutter_contacts: plain `denied` after the first Deny (never
//    notDetermined once asked, and even before on a bad day);
//  * device_calendar_plus: `notDetermined` while not granted;
//  * Android: rationale is true after the first Deny, false after a Deny that
//    followed a prompt, after "don't ask again", and while never asked; a
//    blocked permission shows no prompt.

import 'package:dhruva/data/connectors/connector.dart';
import 'package:dhruva/data/connectors/connector_hub.dart';
import 'package:dhruva/data/connectors/connector_sources.dart';
import 'package:dhruva/data/connectors/system_sources.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_connector_sources.dart';

enum Choice { allow, deny, denyForever }

/// Android's permission state plus our native plugin's channel answers.
class AndroidPermissionModel {
  final asked = <String>{};
  final granted = <String>{};
  final blocked = <String>{};
  final denies = <String, int>{};

  /// What the user taps at each prompt, in order (default: Deny).
  final script = <Choice>[];
  int prompts = 0;

  bool rationale(String n) =>
      asked.contains(n) &&
      !granted.contains(n) &&
      !blocked.contains(n) &&
      (denies[n] ?? 0) == 1;

  /// The system prompt itself; shows nothing for a blocked permission.
  void prompt(String n) {
    if (granted.contains(n) || blocked.contains(n)) return;
    prompts++;
    switch (script.isEmpty ? Choice.deny : script.removeAt(0)) {
      case Choice.allow:
        granted.add(n);
      case Choice.deny:
        denies[n] = (denies[n] ?? 0) + 1;
        // Android 11+: a second Deny is final.
        if (denies[n]! >= 2) {
          blocked.add(n);
        }
      case Choice.denyForever:
        denies[n] = 2;
        blocked.add(n);
    }
  }

  Object? handle(MethodCall c) {
    final args = c.arguments;
    final n = args is Map ? args['name'] as String? : null;
    switch (c.method) {
      case 'calendar.permission':
        return granted.contains('calendar') ? 'granted' : 'denied';
      case 'calendar.request':
        prompt('calendar');
        return granted.contains('calendar') ? 'granted' : 'denied';
      case 'permission.asked':
        return asked.contains(n);
      case 'permission.markAsked':
        asked.add(n!);
        return null;
      case 'permission.rationale':
        return rationale(n!);
    }
    return null;
  }
}

/// flutter_contacts: `denied` whenever not granted.
DevicePermission _contactsPlugin(AndroidPermissionModel os) =>
    os.granted.contains('contacts')
    ? DevicePermission.granted
    : DevicePermission.denied;

/// device_calendar_plus: `notDetermined` whenever not granted.
DevicePermission _calendarPlugin(AndroidPermissionModel os) =>
    os.granted.contains('calendar')
    ? DevicePermission.granted
    : DevicePermission.notDetermined;

class _GatedCalendar extends FakeCalendarSource {
  _GatedCalendar(this.gate);
  final PermissionGate gate;
  @override
  Future<DevicePermission> permission() => gate.status();
  @override
  Future<DevicePermission> request() => gate.request();
}

class _GatedContacts extends FakeContactsSource {
  _GatedContacts(this.gate);
  final PermissionGate gate;
  @override
  Future<DevicePermission> permission() => gate.status();
  @override
  Future<DevicePermission> request() => gate.request();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AndroidPermissionModel os;
  late MethodChannel mc;
  late ConnectorsChannel channel;
  late AppDatabase db;
  late ConnectorTestKit kit;
  late ConnectorHub hub;

  PermissionGate gateFor(String name) => PermissionGate(
    name: name,
    channel: channel,
    android: true,
    read: () async =>
        name == 'contacts' ? _contactsPlugin(os) : channel.calendarPermission(),
    ask: () async {
      if (name == 'contacts') {
        os.prompt('contacts'); // flutter_contacts shows the system prompt
        return _contactsPlugin(os);
      }
      return channel.requestCalendarPermission();
    },
  );

  setUp(() {
    os = AndroidPermissionModel();
    mc = const MethodChannel(ConnectorsChannel.channelName);
    channel = ConnectorsChannel(channel: mc);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mc, (c) async => os.handle(c));
    db = AppDatabase(NativeDatabase.memory());
    kit = ConnectorTestKit.create(db);
    hub = ConnectorHub.fromSources(
      db: db,
      calendar: _GatedCalendar(gateFor('calendar')),
      contacts: _GatedContacts(gateFor('contacts')),
      folder: kit.folder,
      notifications: kit.notifications,
      isCharging: () async => false,
      folderCache: kit.tempDir,
      scheduler: FakeScheduler(),
    );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mc, null);
    await hub.dispose();
    await kit.dispose();
    await db.close();
  });

  group('PermissionGate.status', () {
    test('never asked: retryable even when the plugin says denied', () async {
      expect(
        await gateFor('contacts').status(),
        DevicePermission.notDetermined,
      );
      expect(
        await gateFor('calendar').status(),
        DevicePermission.notDetermined,
      );
    });

    test('iOS trusts the plugin: denied is final, notDetermined retries, '
        'no channel calls', () async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(mc, (c) async {
            calls.add(c.method);
            return null;
          });
      PermissionGate ios(DevicePermission plugin) => PermissionGate(
        name: 'contacts',
        channel: channel,
        android: false,
        read: () async => plugin,
        ask: () async => plugin,
      );
      expect(
        await ios(DevicePermission.denied).status(),
        DevicePermission.denied,
      );
      expect(
        await ios(DevicePermission.denied).request(),
        DevicePermission.denied,
      );
      expect(
        await ios(DevicePermission.notDetermined).status(),
        DevicePermission.notDetermined,
      );
      expect(calls, isEmpty);
    });

    test('granted short-circuits', () async {
      os.granted.add('contacts');
      expect(await gateFor('contacts').status(), DevicePermission.granted);
    });
  });

  for (final name in ['contacts', 'calendar']) {
    final pick = name == 'contacts'
        ? (ConnectorHub h) => h.contacts
        : (ConnectorHub h) => h.calendar;

    group('$name on Android', () {
      test('first Deny: retry copy, Connect stays, not final', () async {
        os.script.add(Choice.deny);
        final c = pick(hub);
        await c.connect();
        final s = c.currentStatus;
        expect(s.state, ConnectorState.notConnected);
        expect(s.needsSettings, isFalse);
        expect(s.detail, contains('Tap Connect to try again'));
        expect(c.awaitingGrant, isFalse);
        expect(await hub.store.account(name), isNull);
      });

      test('second Deny: blocked copy and Open settings', () async {
        os.script.addAll([Choice.deny, Choice.deny]);
        final c = pick(hub);
        await c.connect();
        await c.connect();
        final s = c.currentStatus;
        expect(os.prompts, 2);
        expect(s.needsSettings, isTrue);
        expect(s.detail, contains('blocked'));
        expect(s.detail, contains('Open settings'));
        expect(c.awaitingGrant, isTrue);
      });

      test("'Don't ask again' on the first prompt: blocked at once", () async {
        os.script.add(Choice.denyForever);
        final c = pick(hub);
        await c.connect();
        expect(c.currentStatus.needsSettings, isTrue);
        expect(c.currentStatus.detail, contains('Open settings'));
      });

      test('allow on the retry connects', () async {
        os.script.addAll([Choice.deny, Choice.allow]);
        final c = pick(hub);
        await c.connect();
        await c.connect();
        expect(c.currentStatus.state, ConnectorState.connected);
      });

      test('blocked, then allowed in settings: connects by itself on '
          'resume', () async {
        os.script.addAll([Choice.deny, Choice.deny]);
        final c = pick(hub);
        await c.connect();
        await c.connect();
        expect(c.awaitingGrant, isTrue);

        await hub.onResume(); // back from settings, still not allowed
        expect(c.currentStatus.state, ConnectorState.notConnected);
        expect(c.awaitingGrant, isTrue);

        os.granted.add(name); // allowed in system settings
        await hub.onResume();
        expect(c.currentStatus.state, ConnectorState.connected);
        expect(c.awaitingGrant, isFalse);
        expect(await hub.store.account(name), isNotNull);
      });

      test('the asked flag survives a restart (a fresh gate)', () async {
        os.script.add(Choice.deny);
        await pick(hub).connect();
        expect(
          await gateFor(name).status(),
          DevicePermission.notDetermined,
          reason: 'first Deny is still retryable after a restart',
        );
        os.script.add(Choice.deny);
        await gateFor(name).request();
        expect(await gateFor(name).status(), DevicePermission.denied);
      });
    });
  }

  test('calendar plugin quirk (notDetermined) and contacts quirk (denied) '
      'both read as retryable after one Deny', () async {
    os.script.addAll([Choice.deny, Choice.deny]);
    await hub.contacts.connect();
    await hub.calendar.connect();
    expect(_contactsPlugin(os), DevicePermission.denied);
    expect(_calendarPlugin(os), DevicePermission.notDetermined);
    expect(hub.contacts.currentStatus.needsSettings, isFalse);
    expect(hub.calendar.currentStatus.needsSettings, isFalse);
  });
}
