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

  /// In sync order.
  List<Connector> get all => [calendar, folder, notifications, contacts];

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
      contacts: const SystemContactsSource(),
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
