/// The seams between a connector and the phone: one small interface per
/// source. Production implementations live in `system_sources.dart`; tests use
/// the fakes in `test/support/fake_connector_sources.dart`.
library;

import 'connector.dart';

/// An OS permission as the connectors care about it.
enum DevicePermission {
  granted,

  /// Never asked, or asked and dismissed: a prompt can still be shown.
  notDetermined,

  /// Denied (or blocked by policy). Only the OS settings page can fix it.
  denied,
}

// ---- calendar ------------------------------------------------------------

final class DeviceCalendarEvent {
  /// Stable per occurrence (a recurring series has one id per instance).
  final String id;
  final String calendarId;
  final String? calendarName;
  final String title;
  final String? description;
  final String? location;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final bool recurring;
  final List<Person> attendees;

  const DeviceCalendarEvent({
    required this.id,
    required this.calendarId,
    required this.start,
    required this.end,
    this.calendarName,
    this.title = '',
    this.description,
    this.location,
    this.allDay = false,
    this.recurring = false,
    this.attendees = const [],
  });
}

/// Read-only view of the device calendar.
abstract interface class CalendarSource {
  Future<DevicePermission> permission();
  Future<DevicePermission> request();

  /// Events overlapping `[from, to)` across every calendar the user has.
  Future<List<DeviceCalendarEvent>> events(DateTime from, DateTime to);
  Future<void> openSettings();
}

// ---- contacts ------------------------------------------------------------

final class DeviceContact {
  /// The OS contact id, or null if the OS gave none.
  final String? id;
  final String name;

  /// Small avatar bytes, if the contact has a photo.
  final List<int>? thumbnail;
  const DeviceContact({this.id, required this.name, this.thumbnail});
}

/// Read-only lookup of ONE person by email. There is deliberately no
/// "list everything" method: the address book is never bulk-read.
abstract interface class ContactsSource {
  Future<DevicePermission> permission();
  Future<DevicePermission> request();
  Future<DeviceContact?> byEmail(String email);
  Future<void> openSettings();
}

// ---- folder --------------------------------------------------------------

/// A folder the user granted through the system picker. [id] is opaque (an
/// Android tree uri, an iOS bookmark key); only the native side interprets it.
final class FolderGrant {
  final String id;
  final String name;
  const FolderGrant({required this.id, required this.name});
}

final class FolderEntry {
  /// Opaque and stable per file (Android document uri, iOS relative path).
  final String id;
  final String name;
  final int size;
  final DateTime modified;
  const FolderEntry({
    required this.id,
    required this.name,
    required this.size,
    required this.modified,
  });
}

/// Why a file could not be copied out of the granted folder.
final class FolderFetchException implements Exception {
  final String message;
  const FolderFetchException(this.message);
  @override
  String toString() => 'FolderFetchException: $message';
}

abstract interface class FolderSource {
  /// Opens the system folder picker. Null when the user cancels.
  Future<FolderGrant?> pick();

  /// Whether the grant still resolves (folder moved, deleted or revoked).
  /// Throws [TimeoutException] when the platform did not answer in time:
  /// unknown, NOT unreachable.
  Future<bool> isReachable(String grantId);

  /// Files (never directories) at any depth under the grant, at most
  /// [maxFiles]. The native side never leaves the granted tree (iOS also
  /// skips symlinks; on Android the document provider decides what a link is,
  /// and fetch re-checks that the document is under the root).
  Future<List<FolderEntry>> list(String grantId, {required int maxFiles});

  /// Copies one file into [destPath] (a path inside this app's cache), reading
  /// at most [maxBytes]. Throws [FolderFetchException].
  Future<void> fetch(
    String grantId,
    FolderEntry entry,
    String destPath, {
    required int maxBytes,
  });

  /// Releases the persistent grant.
  Future<void> release(String grantId);
  Future<void> openSettings();
}

// ---- notifications ---------------------------------------------------------

abstract interface class NotificationAccess {
  /// False on iOS: the connector reports `unsupported` and the UI hides it.
  bool get supported;

  /// Whether the user switched notification access on for this app.
  Future<bool> isGranted();
  Future<void> openSettings();

  /// The native listener only records while this is true (off by default; set
  /// on connect, cleared on revoke).
  Future<void> setCapture(bool enabled);
  Future<void> setExcludedPackages(List<String> packages);

  /// App-private directory the native listener appends its queue to.
  Future<String?> queueDirectory();
}

/// Whether the phone is charging (folder indexing runs only then, unless the
/// user asks).
typedef ChargingProbe = Future<bool> Function();

// ---- hand-off to other apps -------------------------------------------------

/// Why [ExternalOpener] could not open something; [message] is user-ready.
final class OpenFailure implements Exception {
  final String message;
  const OpenFailure(this.message);
  @override
  String toString() => 'OpenFailure: $message';
}

/// Hands a file or an app over to the phone: the OS viewer for a file of the
/// connected folder, the launcher for the app a notification came from. Both
/// are user-tapped, read-only hand-offs; nothing here reads content.
abstract interface class ExternalOpener {
  /// Opens [entryId] (a file inside the folder granted as [grantId]) in the
  /// phone's own viewer. Throws [OpenFailure] with a reason the user can act on.
  Future<void> openFile(String grantId, String entryId);

  /// Launches the app [package]. False when it is gone or has no launcher entry.
  Future<bool> launchApp(String package);
}
