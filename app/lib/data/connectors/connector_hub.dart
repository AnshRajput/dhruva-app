/// Composition root for the connectors: builds the store, the four connectors
/// and the sync service from one database and one set of OS seams. The app
/// (Riverpod) and the WorkManager background entry point both go through this,
/// so they cannot drift apart.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/database.dart';
import '../docs/document_extractor.dart' show DocumentExtractor;
import 'background_sync.dart';
import 'base_connector.dart';
import 'calendar_connector.dart';
import 'connector.dart';
import 'connector_sources.dart';
import 'connector_store.dart';
import 'contacts_connector.dart';
import 'folder_connector.dart';
import 'notification_connector.dart';
import 'sync_service.dart';
import 'system_sources.dart';

final class ConnectorHub {
  ConnectorHub({
    required this.store,
    required this.calendar,
    required this.contacts,
    required this.folder,
    required this.notifications,
    this.scheduler = const WorkmanagerSyncScheduler(),
  }) : sync = SyncService(
         connectors: [calendar, contacts, folder, notifications],
         clock: () => store.now,
       ) {
    for (final c in [calendar, contacts, folder, notifications]) {
      c.onConnectionChanged = syncBackgroundJob;
    }
  }

  final ConnectorStore store;
  final CalendarConnector calendar;
  final ContactsConnector contacts;
  final FolderConnector folder;
  final NotificationConnector notifications;
  final SyncService sync;
  final BackgroundSyncScheduler scheduler;
  bool _jobScheduled = false;

  /// The one place the periodic background job is started or stopped: runs
  /// after every connect/revoke and at app launch. Starts it when something is
  /// connected (once per process; the job itself is idempotent), cancels it
  /// when nothing is.
  Future<void> syncBackgroundJob() async {
    final any = all.any((c) => c.currentStatus.isConnected);
    if (any && !_jobScheduled) {
      _jobScheduled = true;
      await scheduler.schedule();
    } else if (!any) {
      // Always cancel, even if this process never scheduled: the job may be
      // left over from a previous launch. Cancelling nothing is harmless.
      _jobScheduled = false;
      await scheduler.cancel();
    }
  }

  /// App resume: re-reads every OS grant (so access given or taken away in
  /// system settings shows up at once), finishes a first-time connect the user
  /// just completed in system settings (calendar, contacts), reads right away
  /// from a source that just became usable, drains the notification queue (a
  /// new notification is in the Inbox now, not at the next 6 h job or the
  /// 10-minute throttle), then keeps the background job in step with what is
  /// connected.
  Future<void> onResume() async {
    final before = {for (final c in all) c.id: c.currentStatus.state};
    await Future.wait(all.map((c) => c.refreshStatus()));
    final synced = <String>{};
    for (final c in all) {
      if (c is BaseConnector && c.awaitingGrant) {
        try {
          if (await c.grantedNow()) {
            await c.connect();
            if (c.currentStatus.isConnected) {
              await c.sync();
              synced.add(c.id);
            }
          }
        } catch (_) {
          // The row shows what is wrong; resume must not throw.
        }
      }
    }
    for (final c in all) {
      if (synced.contains(c.id)) continue;
      final was = before[c.id];
      final fixed =
          c.currentStatus.state == ConnectorState.connected &&
          (was == ConnectorState.needsAttention ||
              was == ConnectorState.permissionDenied);
      if (!fixed) continue;
      try {
        await c.sync();
        synced.add(c.id);
      } catch (_) {
        // The card shows what is wrong; resume must not throw.
      }
    }
    if (!synced.contains(ConnectorIds.notifications)) {
      await sync.drainNotifications();
    }
    await syncBackgroundJob();
  }

  /// In display order (Connectors screen). Sync order is
  /// `ConnectorIds.syncOrder`: contacts run last there.
  List<Connector> get all => [calendar, contacts, folder, notifications];

  Connector? byId(String id) {
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// The real thing: OS-backed sources over [db].
  static Future<ConnectorHub> system(AppDatabase db) async {
    final channel = ConnectorsChannel();
    final cache = await getTemporaryDirectory();
    return ConnectorHub.fromSources(
      db: db,
      calendar: SystemCalendarSource(channel),
      contacts: SystemContactsSource(channel),
      folder: SystemFolderSource(channel),
      notifications: SystemNotificationAccess(channel),
      isCharging: chargingProbe(channel),
      folderCache: Directory(p.join(cache.path, 'connector_files')),
    );
  }

  factory ConnectorHub.fromSources({
    required AppDatabase db,
    required CalendarSource calendar,
    required ContactsSource contacts,
    required FolderSource folder,
    required NotificationAccess notifications,
    required ChargingProbe isCharging,
    required Directory folderCache,
    DocumentExtractor? extractor,
    DateTime Function()? clock,
    BackgroundSyncScheduler scheduler = const WorkmanagerSyncScheduler(),
  }) {
    final store = ConnectorStore(db: db, clock: clock);
    return ConnectorHub(
      store: store,
      calendar: CalendarConnector(store: store, source: calendar),
      contacts: ContactsConnector(store: store, source: contacts),
      folder: FolderConnector(
        store: store,
        source: folder,
        cacheDirectory: folderCache,
        isCharging: isCharging,
        extractor: extractor,
      ),
      notifications: NotificationConnector(store: store, access: notifications),
      scheduler: scheduler,
    );
  }

  Future<void> dispose() async {
    for (final c in [calendar, contacts, folder, notifications]) {
      await c.dispose();
    }
  }
}
