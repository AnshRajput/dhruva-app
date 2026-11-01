/// Android notification digest. The Kotlin `NotificationListenerService`
/// appends each notification (title, text, app, time) to an app-private queue
/// file; this connector drains that queue into the store on app open / sync.
///
/// Off by default: the listener records nothing until [connect] switches
/// capture on AND the user has granted notification access in system settings.
/// Revoking switches capture off and wipes everything stored. iOS cannot read
/// other apps' notifications, so there the connector is `unsupported` and the
/// UI hides it.
library;

import 'dart:io';

import 'base_connector.dart';
import 'connector.dart';
import 'connector_sources.dart';
import 'connector_store.dart';
import 'notification_queue.dart';
import 'otp_guard.dart';

/// Notifications older than this are dropped at each sync.
const notificationRetention = Duration(days: 7);

/// This app's own id: its notifications are never captured.
const ownApplicationId = 'app.dhruva.mobile';

class NotificationConnector extends BaseConnector {
  NotificationConnector({required ConnectorStore store, required this.access})
    : super(store);

  final NotificationAccess access;

  // Drained on every resume, Inbox open and pull-to-refresh: an empty drain is
  // not worth a ledger row.
  @override
  bool get logEmptyReads => false;

  @override
  String get id => ConnectorIds.notifications;

  @override
  String get displayName => 'Notifications';

  static const _off =
      'Notification access is off. Open settings and switch it on for this '
      'app to see your notification digest.';

  @override
  ConnectorStatus get currentStatus =>
      access.supported ? super.currentStatus : ConnectorStatus.unsupported;

  Set<String> _excluded(ConnectorAccount? a) => {
    ownApplicationId,
    for (final e in (a?.config['excluded'] as List?) ?? const [])
      if (e is String) e,
  };

  @override
  Future<ConnectorStatus> evaluate(ConnectorAccount? account) async {
    if (!access.supported) return ConnectorStatus.unsupported;
    if (account == null) return ConnectorStatus.notConnected;
    if (!await access.isGranted()) {
      return ConnectorStatus(
        ConnectorState.needsAttention,
        detail: _off,
        lastSyncAt: account.lastSyncAt,
      );
    }
    if (account.lastError != null) {
      return ConnectorStatus(
        ConnectorState.needsAttention,
        detail: account.lastError,
        lastSyncAt: account.lastSyncAt,
      );
    }
    return ConnectorStatus(
      ConnectorState.connected,
      lastSyncAt: account.lastSyncAt,
    );
  }

  @override
  Future<ConnectorStatus> doConnect() async {
    if (!access.supported) return ConnectorStatus.unsupported;
    final account = await store.account(id);
    await store.saveAccount(
      id,
      status: 'connected',
      clearError: true,
      config: account?.config ?? const {},
    );
    // Capture is armed first, so the moment the user flips the system switch
    // the listener starts recording; the OS page is where the grant happens.
    await access.setCapture(true);
    await access.setExcludedPackages(
      _excluded(await store.account(id)).toList(),
    );
    if (await access.isGranted()) return evaluate(await store.account(id));
    await access.openSettings();
    return const ConnectorStatus(ConnectorState.needsAttention, detail: _off);
  }

  @override
  Future<SyncResult> doSync(ConnectorAccount account, DateTime? since) async {
    final dir = await access.queueDirectory();
    if (dir == null) {
      throw const ConnectorException(
        ConnectorState.needsAttention,
        'Could not open the notification queue. Try again.',
      );
    }
    final now = store.now;
    final batch = await NotificationQueue(
      Directory(dir),
    ).drain(now: now, excluded: _excluded(account));
    final drafts = [
      for (final n in batch.notifications)
        if (looksLikeVerificationCode(n.title, n.text))
          // The code is dropped here, before anything is stored: the title
          // may carry it too, so the app name stands in for it.
          ItemDraft(
            externalId: n.dedupeId,
            kind: ItemKind.notification,
            title: n.app,
            body: hiddenCodeBody,
            sentAt: n.time,
            flags: {'pkg': n.pkg, 'app': n.app, otpFlag: true},
          )
        else
          ItemDraft(
            externalId: n.dedupeId,
            kind: ItemKind.notification,
            title: n.title.isEmpty ? n.app : n.title,
            body: n.text,
            sentAt: n.time,
            flags: {'pkg': n.pkg, 'app': n.app},
          ),
    ];
    final result = await store.upsertItems(id, drafts, requireAccount: true);
    // Only now is it safe to forget the queue files.
    await batch.commit();
    await store.pruneOlderThan(id, now.subtract(notificationRetention));
    // If the user later switched access off, what was captured is kept and
    // read; `evaluate` then shows the "turn access back on" card.
    return SyncResult(read: drafts.length, changed: result.changed);
  }

  /// Apps whose notifications are never recorded (by package id).
  Future<void> setExcludedApps(List<String> packages) async {
    final account = await store.account(id);
    if (account == null) return;
    await store.saveAccount(
      id,
      config: {...account.config, 'excluded': packages},
    );
    await access.setExcludedPackages(
      _excluded(await store.account(id)).toList(),
    );
  }

  @override
  Future<void> onRevoke(ConnectorAccount? account) async {
    await access.setCapture(false);
    // Queued, not-yet-ingested notifications are user content too.
    final dir = await access.queueDirectory();
    if (dir == null || !Directory(dir).existsSync()) return;
    for (final e in Directory(dir).listSync()) {
      if (e is File &&
          e.uri.pathSegments.last.startsWith(NotificationQueue.liveName)) {
        e.deleteSync();
      }
    }
  }

  @override
  Future<void> openSystemSettings() => access.openSettings();
}
