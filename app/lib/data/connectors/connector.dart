/// The connector contract: one implementation per source (calendar, contacts,
/// folder, notifications; Gmail later), no plugin system.
///
/// A connector talks to exactly one place on the phone (or, for Gmail later,
/// to the user's own provider), turns what it reads into [ItemDraft]s and hands
/// them to the `ConnectorStore`. It never writes to the OS source, and it never
/// stores credentials in the app database.
library;

import 'dart:async';

import '../db/database.dart' show ItemKind;

export '../db/database.dart' show ItemKind;

/// Stable connector ids. Stored in `items.source`, `connector_accounts` and
/// `ledger`, so never rename a value.
abstract final class ConnectorIds {
  static const calendar = 'calendar';
  static const contacts = 'contacts';
  static const folder = 'folder';
  static const notifications = 'notifications';

  /// Sync order: contacts resolve people found by the others, so it runs last.
  static const syncOrder = [calendar, folder, notifications, contacts];

  /// Sources that fill the Inbox tab (mail later joins this set).
  static const inboxSources = {notifications};
}

/// What the Settings card shows for a connector.
enum ConnectorState {
  /// This platform cannot offer the connector at all (notifications on iOS).
  /// The UI hides it.
  unsupported,

  /// The user has not opted in.
  notConnected,

  /// The user opted in and the OS grant is in place.
  connected,

  /// A sync is running.
  syncing,

  /// The user denied (or later revoked) the OS permission. The fix is the OS
  /// settings page: the UI shows "Open settings".
  permissionDenied,

  /// Opted in but something needs the user: the folder is gone, access was
  /// switched off, the last sync failed. [ConnectorStatus.detail] names the fix.
  needsAttention,
}

/// Immutable snapshot of a connector's standing.
final class ConnectorStatus {
  final ConnectorState state;

  /// A sentence that names what happened and the fix ("Calendar access is
  /// off. Open settings to turn it on."). Null when all is well.
  final String? detail;
  final DateTime? lastSyncAt;

  const ConnectorStatus(this.state, {this.detail, this.lastSyncAt});

  static const unsupported = ConnectorStatus(ConnectorState.unsupported);
  static const notConnected = ConnectorStatus(ConnectorState.notConnected);

  bool get isConnected =>
      state == ConnectorState.connected || state == ConnectorState.syncing;

  ConnectorStatus copyWith({
    ConnectorState? state,
    String? detail,
    DateTime? lastSyncAt,
  }) => ConnectorStatus(
    state ?? this.state,
    detail: detail,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
  );

  @override
  bool operator ==(Object other) =>
      other is ConnectorStatus &&
      other.state == state &&
      other.detail == detail &&
      other.lastSyncAt == lastSyncAt;

  @override
  int get hashCode => Object.hash(state, detail, lastSyncAt);

  @override
  String toString() => 'ConnectorStatus($state, $detail, $lastSyncAt)';
}

/// What one sync did.
final class SyncResult {
  /// Items the connector read from the source this run.
  final int read;

  /// Items that were new or changed in the local store.
  final int changed;

  /// Why nothing was read ("Waiting for the charger"), or null.
  final String? skipped;

  const SyncResult({this.read = 0, this.changed = 0, this.skipped});

  static const none = SyncResult();
  const SyncResult.skipped(String reason)
    : read = 0,
      changed = 0,
      skipped = reason;
}

/// Why a connector could not do its job; [message] is user-ready.
final class ConnectorException implements Exception {
  final ConnectorState state;
  final String message;
  const ConnectorException(this.state, this.message);

  @override
  String toString() => 'ConnectorException($state): $message';
}

abstract interface class Connector {
  /// One of [ConnectorIds].
  String get id;

  String get displayName;

  /// Emits whenever [currentStatus] changes (also replays nothing: read
  /// [currentStatus] for the first value).
  Stream<ConnectorStatus> get status;
  ConnectorStatus get currentStatus;

  /// Re-reads OS state (permission granted? folder still reachable?) and
  /// updates [status]. Cheap; call on app resume.
  Future<void> refreshStatus();

  /// Starts the opt-in: asks the OS for the permission or access this source
  /// needs. Ends in [ConnectorState.connected], [ConnectorState.permissionDenied]
  /// or [ConnectorState.needsAttention]; never throws for a user "no".
  Future<void> connect();

  /// Reads the source into the local store. [since] lets a source limit the
  /// work; most ignore it. Throws [ConnectorException] when a fix is needed.
  Future<SyncResult> sync({DateTime? since});

  /// Deletes everything this connector stored locally (items, index rows,
  /// content ledger) and stops reading. Keeps one `revoke` ledger row.
  Future<void> revoke();

  /// Opens the OS page where the user can switch this source's permission off
  /// or on again (apps cannot revoke an OS grant themselves).
  Future<void> openSystemSettings();
}

/// A person attached to an item (attendee, sender).
final class Person {
  final String? name;
  final String? email;
  const Person({this.name, this.email});

  Map<String, Object?> toJson() => {
    if (name != null) 'name': name,
    if (email != null) 'email': email,
  };

  static Person? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final email = raw['email'];
    if (name is! String? || email is! String?) return null;
    if (name == null && email == null) return null;
    return Person(name: name, email: email);
  }

  @override
  bool operator ==(Object other) =>
      other is Person && other.name == name && other.email == email;

  @override
  int get hashCode => Object.hash(name, email);
}

/// Hard cap on `items.body`.
const maxItemBodyChars = 8 * 1024;

/// What a connector hands the store. Bodies longer than [maxItemBodyChars] are
/// cut by the store, so no connector can exceed the cap by forgetting.
final class ItemDraft {
  final String externalId;
  final ItemKind kind;
  final String title;
  final String body;
  final List<Person> people;
  final DateTime? startsAt;
  final DateTime? sentAt;
  final Map<String, Object?> flags;

  const ItemDraft({
    required this.externalId,
    required this.kind,
    this.title = '',
    this.body = '',
    this.people = const [],
    this.startsAt,
    this.sentAt,
    this.flags = const {},
  });
}

/// A stored item as the features see it (no drift types: ADR-002).
final class ConnectorItem {
  final int id;
  final String source;
  final String externalId;
  final ItemKind kind;
  final String title;
  final String body;
  final List<Person> people;
  final DateTime? startsAt;
  final DateTime? sentAt;
  final Map<String, Object?> flags;
  final String? summary;
  final String? summaryModel;
  final DateTime updatedAt;

  const ConnectorItem({
    required this.id,
    required this.source,
    required this.externalId,
    required this.kind,
    required this.title,
    required this.body,
    required this.people,
    required this.startsAt,
    required this.sentAt,
    required this.flags,
    required this.summary,
    required this.summaryModel,
    required this.updatedAt,
  });
}

/// One row of the privacy ledger.
final class LedgerEntry {
  final String connector;
  final String action;
  final int count;
  final DateTime at;
  const LedgerEntry({
    required this.connector,
    required this.action,
    required this.count,
    required this.at,
  });
}

/// Ledger `action` values.
abstract final class LedgerAction {
  static const connect = 'connect';
  static const read = 'read';
  static const revoke = 'revoke';
  static const failed = 'failed';
}
