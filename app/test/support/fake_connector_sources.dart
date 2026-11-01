import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dhruva/data/connectors/connector.dart';
import 'package:dhruva/data/connectors/connector_hub.dart';
import 'package:dhruva/data/connectors/connector_sources.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/docs/document_extractor.dart';
import 'package:path/path.dart' as p;

class FakeCalendarSource implements CalendarSource {
  DevicePermission perm;
  DevicePermission afterRequest;
  List<DeviceCalendarEvent> items;
  bool failRead = false;
  int requests = 0;
  int settingsOpened = 0;
  DateTime? lastFrom;
  DateTime? lastTo;

  FakeCalendarSource({
    this.perm = DevicePermission.notDetermined,
    this.afterRequest = DevicePermission.granted,
    this.items = const [],
  });

  @override
  Future<DevicePermission> permission() async => perm;

  @override
  Future<DevicePermission> request() async {
    requests++;
    perm = afterRequest;
    return perm;
  }

  @override
  Future<List<DeviceCalendarEvent>> events(DateTime from, DateTime to) async {
    lastFrom = from;
    lastTo = to;
    if (failRead) throw StateError('provider down');
    return items;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;
}

class FakeContactsSource implements ContactsSource {
  DevicePermission perm;
  DevicePermission afterRequest;
  final Map<String, DeviceContact> byAddress = {};
  final List<String> lookups = [];
  bool failRead = false;
  int settingsOpened = 0;

  FakeContactsSource({
    this.perm = DevicePermission.notDetermined,
    this.afterRequest = DevicePermission.granted,
  });

  @override
  Future<DevicePermission> permission() async => perm;

  @override
  Future<DevicePermission> request() async {
    perm = afterRequest;
    return perm;
  }

  @override
  Future<DeviceContact?> byEmail(String email) async {
    lookups.add(email);
    if (failRead) throw StateError('contacts down');
    return byAddress[email];
  }

  @override
  Future<void> openSettings() async => settingsOpened++;
}

/// An in-memory granted folder. [files] maps entry id -> bytes.
class FakeFolderSource implements FolderSource {
  FolderGrant? nextPick;
  bool reachable = true;
  bool failList = false;
  bool failRelease = false;
  bool ignoreMaxFiles = false;
  final Map<String, Uint8List> files = {};
  final Map<String, FolderEntry> entries = {};
  final List<String> released = [];
  final List<String> fetched = [];
  final Set<String> unreadable = {};
  int settingsOpened = 0;
  int listCalls = 0;

  /// When set, every fetch announces itself on [fetchStarted] and then waits
  /// for this gate (lets a test act while a sync is mid-run).
  Completer<void>? fetchGate;
  Completer<void>? fetchStarted;

  void addFile(String name, String text, {DateTime? modified, String? id}) {
    final bytes = Uint8List.fromList(text.codeUnits);
    final eid = id ?? 'doc:$name';
    files[eid] = bytes;
    entries[eid] = FolderEntry(
      id: eid,
      name: name,
      size: bytes.length,
      modified: modified ?? DateTime.utc(2026, 10, 30),
    );
  }

  @override
  Future<FolderGrant?> pick() async => nextPick;

  @override
  Future<bool> isReachable(String grantId) async => reachable;

  @override
  Future<List<FolderEntry>> list(
    String grantId, {
    required int maxFiles,
  }) async {
    listCalls++;
    if (failList) throw StateError('listing failed');
    return entries.values
        .take(ignoreMaxFiles ? entries.length : maxFiles)
        .toList();
  }

  @override
  Future<void> fetch(
    String grantId,
    FolderEntry entry,
    String destPath, {
    required int maxBytes,
  }) async {
    fetched.add(entry.id);
    if (fetchGate != null) {
      if (fetchStarted != null && !fetchStarted!.isCompleted) {
        fetchStarted!.complete();
      }
      await fetchGate!.future;
    }
    if (unreadable.contains(entry.id)) {
      throw const FolderFetchException('cannot read');
    }
    final bytes = files[entry.id];
    if (bytes == null) throw const FolderFetchException('missing');
    if (bytes.length > maxBytes) throw const FolderFetchException('too large');
    await File(destPath).writeAsBytes(bytes);
  }

  @override
  Future<void> release(String grantId) async {
    released.add(grantId);
    if (failRelease) throw StateError('release failed');
  }

  @override
  Future<void> openSettings() async => settingsOpened++;
}

class FakeNotificationAccess implements NotificationAccess {
  FakeNotificationAccess({
    required this.dir,
    this.supported = true,
    this.granted = false,
  });

  final Directory dir;
  @override
  final bool supported;
  bool granted;
  bool capture = false;
  List<String> excluded = const [];
  int settingsOpened = 0;
  bool failQueueDir = false;

  @override
  Future<bool> isGranted() async => granted;

  @override
  Future<void> openSettings() async => settingsOpened++;

  @override
  Future<void> setCapture(bool enabled) async => capture = enabled;

  @override
  Future<void> setExcludedPackages(List<String> packages) async =>
      excluded = packages;

  @override
  Future<String?> queueDirectory() async => failQueueDir ? null : dir.path;
}

/// Everything a connector test needs, wired over [db].
class ConnectorTestKit {
  ConnectorTestKit._(
    this.hub,
    this.calendar,
    this.contacts,
    this.folder,
    this.notifications,
    this.tempDir,
    this.charging,
  );

  final ConnectorHub hub;
  final FakeCalendarSource calendar;
  final FakeContactsSource contacts;
  final FakeFolderSource folder;
  final FakeNotificationAccess notifications;
  final Directory tempDir;
  final ChargingState charging;

  Directory get queueDir => notifications.dir;

  static ConnectorTestKit create(
    AppDatabase db, {
    DateTime Function()? clock,
    bool notificationsSupported = true,
    DocumentExtractor? extractor,
  }) {
    final temp = Directory.systemTemp.createTempSync('dhruva_connector_kit');
    final queue = Directory(p.join(temp.path, 'queue'))..createSync();
    final cal = FakeCalendarSource();
    final con = FakeContactsSource();
    final fol = FakeFolderSource();
    final not = FakeNotificationAccess(
      dir: queue,
      supported: notificationsSupported,
    );
    final charging = ChargingState();
    final hub = ConnectorHub.fromSources(
      db: db,
      calendar: cal,
      contacts: con,
      folder: fol,
      notifications: not,
      isCharging: () async => charging.next(),
      folderCache: Directory(p.join(temp.path, 'cache')),
      extractor: extractor,
      clock: clock,
    );
    return ConnectorTestKit._(hub, cal, con, fol, not, temp, charging);
  }

  Future<void> dispose() async {
    await hub.dispose();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  }
}

class ChargingState {
  bool value = false;

  /// If set, successive checks consume it (the last value then repeats).
  List<bool>? script;

  bool next() {
    final s = script;
    if (s == null || s.isEmpty) return value;
    return s.length > 1 ? s.removeAt(0) : s.first;
  }
}

DeviceCalendarEvent calEvent(
  String id, {
  String title = 'Standup',
  required DateTime start,
  String calendarId = 'cal1',
  List<Person> attendees = const [],
  String? location,
  String? description,
}) => DeviceCalendarEvent(
  id: id,
  calendarId: calendarId,
  title: title,
  start: start,
  end: start.add(const Duration(hours: 1)),
  attendees: attendees,
  location: location,
  description: description,
);
