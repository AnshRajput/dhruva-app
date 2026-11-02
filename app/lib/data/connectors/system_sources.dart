/// Production implementations of the connector seams (`connector_sources.dart`).
///
///  * Calendar: Android reads through our own native code with READ_CALENDAR
///    only (device_calendar_plus 0.8 insists on WRITE_CALENDAR for any read
///    access, which a read-only assistant must not request); iOS uses
///    `device_calendar_plus` (EventKit full access, read calls only).
///  * Contacts: `flutter_contacts`, one lookup by email at a time.
///  * Folder / notifications / charging: the `app.dhruva/connectors` platform
///    channel, implemented by the local `dhruva_connectors` plugin (Kotlin on
///    Android, Swift on iOS). It lives in a plugin, not in MainActivity, so the
///    WorkManager background engine can reach it too.
///
/// Platform glue: exercised on devices and through a mocked channel in
/// `test/data/connectors/connectors_channel_test.dart`.
library;

import 'dart:async';

import 'package:device_calendar_plus/device_calendar_plus.dart' as dc;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;

import 'connector.dart';
import 'connector_sources.dart';

/// Thin typed wrapper over the platform channel. Parsing is defensive: a
/// malformed map from native code is dropped, never thrown.
class ConnectorsChannel {
  ConnectorsChannel({MethodChannel? channel})
    : _ch = channel ?? const MethodChannel(channelName);

  static const channelName = 'app.dhruva/connectors';
  final MethodChannel _ch;

  static DevicePermission parsePermission(Object? raw) => switch (raw) {
    'granted' => DevicePermission.granted,
    'notDetermined' => DevicePermission.notDetermined,
    _ => DevicePermission.denied,
  };

  Future<DevicePermission> calendarPermission() async =>
      parsePermission(await _ch.invokeMethod<String>('calendar.permission'));

  Future<DevicePermission> requestCalendarPermission() async =>
      parsePermission(await _ch.invokeMethod<String>('calendar.request'));

  Future<List<DeviceCalendarEvent>> calendarEvents(
    DateTime from,
    DateTime to,
  ) async {
    final raw = await _ch.invokeListMethod<Object?>('calendar.events', {
      'from': from.millisecondsSinceEpoch,
      'to': to.millisecondsSinceEpoch,
    });
    return [for (final m in raw ?? const <Object?>[]) ?parseCalendarEvent(m)];
  }

  /// Public for tests.
  static DeviceCalendarEvent? parseCalendarEvent(Object? m) {
    if (m is! Map) return null;
    final id = m['id'];
    final calendarId = m['calendarId'];
    final start = m['start'];
    final end = m['end'];
    if (id is! String || id.isEmpty || calendarId is! String) return null;
    if (start is! int || end is! int) return null;
    String? str(String k) => m[k] is String ? m[k] as String : null;
    return DeviceCalendarEvent(
      id: id,
      calendarId: calendarId,
      calendarName: str('calendarName'),
      title: str('title') ?? '',
      description: str('description'),
      location: str('location'),
      start: DateTime.fromMillisecondsSinceEpoch(start),
      end: DateTime.fromMillisecondsSinceEpoch(end),
      allDay: m['allDay'] == true,
      recurring: m['recurring'] == true,
      attendees: [
        for (final a in (m['attendees'] as List?) ?? const [])
          ?Person.fromJson(a),
      ],
    );
  }

  Future<void> openAppSettings() => _ch.invokeMethod<void>('app.settings');

  /// Android only. Whether this app has ever shown [name]'s ('calendar',
  /// 'contacts') system prompt. Stored natively so it survives restarts.
  Future<bool> permissionAsked(String name) async =>
      (await _ch.invokeMethod<bool>('permission.asked', {'name': name})) ??
      false;

  Future<void> markPermissionAsked(String name) =>
      _ch.invokeMethod<void>('permission.markAsked', {'name': name});

  /// Android only: `shouldShowRequestPermissionRationale`. True after a Deny
  /// the system will prompt again for; false when never asked or blocked.
  Future<bool> permissionRationale(String name) async =>
      (await _ch.invokeMethod<bool>('permission.rationale', {'name': name})) ??
      false;

  Future<FolderGrant?> pickFolder() async {
    final m = await _ch.invokeMapMethod<String, Object?>('folder.pick');
    if (m == null) return null;
    final id = m['id'];
    final name = m['name'];
    if (id is! String || id.isEmpty) return null;
    return FolderGrant(id: id, name: name is String ? name : 'Folder');
  }

  Future<bool> folderReachable(String grantId) async =>
      (await _ch.invokeMethod<bool>('folder.reachable', {'id': grantId})) ??
      false;

  Future<List<FolderEntry>> listFolder(String grantId, int maxFiles) async {
    final raw = await _ch.invokeListMethod<Object?>('folder.list', {
      'id': grantId,
      'maxFiles': maxFiles,
    });
    final out = <FolderEntry>[];
    for (final m in raw ?? const <Object?>[]) {
      if (m is! Map) continue;
      final id = m['id'];
      final name = m['name'];
      final size = m['size'];
      final modified = m['modified'];
      if (id is! String || id.isEmpty || name is! String) continue;
      if (size is! int || modified is! int) continue;
      out.add(
        FolderEntry(
          id: id,
          name: name,
          size: size,
          modified: DateTime.fromMillisecondsSinceEpoch(modified),
        ),
      );
    }
    return out;
  }

  Future<void> fetchFolderFile(
    String grantId,
    String entryId,
    String destPath,
    int maxBytes,
  ) async {
    try {
      await _ch.invokeMethod<void>('folder.fetch', {
        'id': grantId,
        'entryId': entryId,
        'dest': destPath,
        'maxBytes': maxBytes,
      });
    } on PlatformException catch (e) {
      throw FolderFetchException(e.message ?? e.code);
    }
  }

  Future<void> openFolderFile(String grantId, String entryId) => _ch
      .invokeMethod<void>('folder.open', {'id': grantId, 'entryId': entryId});

  Future<bool> launchApp(String package) async =>
      (await _ch.invokeMethod<bool>('apps.launch', {'package': package})) ??
      false;

  Future<void> releaseFolder(String grantId) =>
      _ch.invokeMethod<void>('folder.release', {'id': grantId});

  Future<bool> notificationAccessGranted() async =>
      (await _ch.invokeMethod<bool>('notifications.granted')) ?? false;

  Future<void> openNotificationSettings() =>
      _ch.invokeMethod<void>('notifications.settings');

  Future<void> setNotificationCapture(bool enabled) =>
      _ch.invokeMethod<void>('notifications.capture', {'enabled': enabled});

  Future<void> setExcludedPackages(List<String> packages) =>
      _ch.invokeMethod<void>('notifications.excluded', {'packages': packages});

  Future<String?> notificationQueueDirectory() =>
      _ch.invokeMethod<String>('notifications.queueDir');

  Future<bool> isCharging() async =>
      (await _ch.invokeMethod<bool>('power.charging')) ?? false;
}

// ---- permission truth ------------------------------------------------------

/// "Can the system still ask?" for Calendar and Contacts, decided from the
/// platform, not from a plugin's enum: `flutter_contacts` reports plain
/// `denied` after the very first Deny, `device_calendar_plus` reports
/// `notDetermined`, and neither tells a retryable Deny from a blocked one.
///
///  * Android: not granted + never asked -> [DevicePermission.notDetermined];
///    asked and the system would still prompt (rationale true, i.e. after the
///    first Deny) -> notDetermined; asked and rationale false (a Deny that
///    followed a prompt, "don't ask again", or blocked) -> denied.
///  * iOS: the system prompts once, so the plugin's answer is already right
///    (denied is final, only Settings can change it).
class PermissionGate {
  PermissionGate({
    required this.name,
    required this.channel,
    required this.read,
    required this.ask,
    required this.android,
  });

  /// 'calendar' or 'contacts': the key for the asked flag and the permission.
  final String name;
  final ConnectorsChannel channel;
  final bool android;

  /// The plugin's own check / prompt. Only "granted or not" is trusted.
  final Future<DevicePermission> Function() read;
  final Future<DevicePermission> Function() ask;

  Future<DevicePermission> status() async {
    final raw = await read();
    if (raw == DevicePermission.granted || !android) return raw;
    if (!await channel.permissionAsked(name)) {
      return DevicePermission.notDetermined;
    }
    return await channel.permissionRationale(name)
        ? DevicePermission.notDetermined
        : DevicePermission.denied;
  }

  Future<DevicePermission> request() async {
    // Marked before the prompt: if the process dies behind it, we still know.
    if (android) await channel.markPermissionAsked(name);
    final raw = await ask();
    return raw == DevicePermission.granted ? raw : status();
  }
}

// ---- calendar ------------------------------------------------------------

class SystemCalendarSource implements CalendarSource {
  SystemCalendarSource(this._channel, {bool? android})
    : _android = android ?? defaultTargetPlatform == TargetPlatform.android {
    _gate = PermissionGate(
      name: 'calendar',
      channel: _channel,
      android: _android,
      read: () async => _android
          ? _channel.calendarPermission()
          : _map(await dc.DeviceCalendar.instance.hasPermissions()),
      ask: () async => _android
          ? _channel.requestCalendarPermission()
          : _map(await dc.DeviceCalendar.instance.requestPermissions()),
    );
  }

  final ConnectorsChannel _channel;
  final bool _android;
  late final PermissionGate _gate;

  static DevicePermission _map(dc.CalendarPermissionStatus s) => switch (s) {
    dc.CalendarPermissionStatus.granted => DevicePermission.granted,
    dc.CalendarPermissionStatus.notDetermined => DevicePermission.notDetermined,
    _ => DevicePermission.denied,
  };

  @override
  Future<DevicePermission> permission() => _gate.status();

  @override
  Future<DevicePermission> request() => _gate.request();

  @override
  Future<List<DeviceCalendarEvent>> events(DateTime from, DateTime to) async {
    if (_android) return _channel.calendarEvents(from, to);
    final events = await dc.DeviceCalendar.instance.listEvents(from, to);
    return [
      for (final e in events)
        DeviceCalendarEvent(
          id: e.instanceId,
          calendarId: e.calendarId,
          title: e.title,
          description: e.description,
          location: e.location,
          start: e.startDate,
          end: e.endDate,
          allDay: e.isAllDay,
          recurring: e.isRecurring,
          attendees: [
            for (final a in e.attendees ?? const <dc.Attendee>[])
              if (a.name != null || a.emailAddress != null)
                Person(name: a.name, email: a.emailAddress),
          ],
        ),
    ];
  }

  @override
  Future<void> openSettings() async => _android
      ? _channel.openAppSettings()
      : dc.DeviceCalendar.instance.openAppSettings();
}

// ---- contacts ------------------------------------------------------------

class SystemContactsSource implements ContactsSource {
  SystemContactsSource(ConnectorsChannel channel, {bool? android})
    : _gate = PermissionGate(
        name: 'contacts',
        channel: channel,
        android: android ?? defaultTargetPlatform == TargetPlatform.android,
        read: () async => _map(
          await fc.FlutterContacts.permissions.check(fc.PermissionType.read),
        ),
        ask: () async => _map(
          await fc.FlutterContacts.permissions.request(fc.PermissionType.read),
        ),
      );

  final PermissionGate _gate;

  static DevicePermission _map(fc.PermissionStatus s) => switch (s) {
    fc.PermissionStatus.granted ||
    fc.PermissionStatus.limited => DevicePermission.granted,
    fc.PermissionStatus.notDetermined => DevicePermission.notDetermined,
    _ => DevicePermission.denied,
  };

  @override
  Future<DevicePermission> permission() => _gate.status();

  @override
  Future<DevicePermission> request() => _gate.request();

  @override
  Future<DeviceContact?> byEmail(String email) async {
    final found = await fc.FlutterContacts.getAll(
      filter: fc.ContactFilter.email(email),
      properties: {fc.ContactProperty.name, fc.ContactProperty.photoThumbnail},
      limit: 1,
    );
    if (found.isEmpty) return null;
    final c = found.first;
    final name = c.displayName;
    if (name == null || name.trim().isEmpty) return null;
    return DeviceContact(id: c.id, name: name, thumbnail: c.photo?.thumbnail);
  }

  @override
  Future<void> openSettings() => fc.FlutterContacts.permissions.openSettings();
}

// ---- folder / notifications / power ----------------------------------------

class SystemFolderSource implements FolderSource {
  SystemFolderSource(this._channel);
  final ConnectorsChannel _channel;

  @override
  Future<FolderGrant?> pick() => _channel.pickFolder();

  @override
  Future<bool> isReachable(String grantId) async {
    try {
      return await _channel.folderReachable(grantId);
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<List<FolderEntry>> list(String grantId, {required int maxFiles}) =>
      _channel.listFolder(grantId, maxFiles);

  @override
  Future<void> fetch(
    String grantId,
    FolderEntry entry,
    String destPath, {
    required int maxBytes,
  }) => _channel.fetchFolderFile(grantId, entry.id, destPath, maxBytes);

  @override
  Future<void> release(String grantId) => _channel.releaseFolder(grantId);

  @override
  Future<void> openSettings() => _channel.openAppSettings();
}

class SystemNotificationAccess implements NotificationAccess {
  SystemNotificationAccess(this._channel);
  final ConnectorsChannel _channel;

  @override
  bool get supported => defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool> isGranted() async {
    if (!supported) return false;
    try {
      return await _channel.notificationAccessGranted();
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> openSettings() => _channel.openNotificationSettings();

  @override
  Future<void> setCapture(bool enabled) =>
      _channel.setNotificationCapture(enabled);

  @override
  Future<void> setExcludedPackages(List<String> packages) =>
      _channel.setExcludedPackages(packages);

  @override
  Future<String?> queueDirectory() => _channel.notificationQueueDirectory();
}

class SystemExternalOpener implements ExternalOpener {
  SystemExternalOpener(this._channel);
  final ConnectorsChannel _channel;

  @override
  Future<void> openFile(String grantId, String entryId) async {
    try {
      await _channel.openFolderFile(grantId, entryId);
    } on MissingPluginException {
      throw const OpenFailure(
        'Opening files from here is not available on this phone yet. You can '
        'still ask about the file.',
      );
    } on PlatformException catch (e) {
      throw OpenFailure(switch (e.code) {
        'no_viewer' => 'No app on this phone can open that file.',
        'denied' || 'outside_grant' =>
          'Access to the folder was switched off. Choose the folder again in '
              'Connectors.',
        _ => 'Could not open the file. Check that it still exists.',
      });
    }
  }

  @override
  Future<bool> launchApp(String package) async {
    try {
      return await _channel.launchApp(package);
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

/// Charging state through the same channel (the device-health channel is not
/// registered in the WorkManager background engine; this one is).
ChargingProbe chargingProbe(ConnectorsChannel channel) => () async {
  try {
    return await channel.isCharging();
  } catch (_) {
    return false;
  }
};
