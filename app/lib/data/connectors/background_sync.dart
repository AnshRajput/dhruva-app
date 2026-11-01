/// Android periodic sync through WorkManager (the `workmanager` package: MIT,
/// maintained by fluttercommunity, no network use).
///
/// Every 6 hours, with the battery-not-low constraint. WorkManager ANDs its
/// constraints, so "charging OR battery not low" is expressed as battery-not-low
/// alone: the system treats a charging phone as not low. Folder indexing is
/// heavier and gates itself on the charger inside `FolderConnector`, so the
/// background run never indexes files on battery.
///
/// iOS: none. Background fetch is best effort and unpredictable, and the iOS
/// connectors (calendar, contacts, folder) are cheap to refresh when the app
/// opens, which is when the brief is built anyway. Nothing is registered there.
///
/// The background run uses a fresh headless Flutter engine: it opens its own
/// database connection and rebuilds the hub through the same [ConnectorHub]
/// the app uses. The native `dhruva_connectors` plugin is registered in that
/// engine too, so calendar, folder and the notification queue work headless.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../db/database.dart';
import 'connector_hub.dart';

const backgroundSyncUniqueName = 'dhruva.connectors.sync';
const backgroundSyncTask = 'connectors.sync';
const backgroundSyncEvery = Duration(hours: 6);

/// Runs one background pass over [hub]. Failures are already recorded on each
/// connector (status + ledger), so the job reports success either way; a retry
/// loop would only drain the battery the constraint protects.
Future<bool> runConnectorSync(ConnectorHub hub) async {
  await hub.sync.refresh();
  return true;
}

@pragma('vm:entry-point')
void connectorSyncDispatcher() {
  Workmanager().executeTask((task, input) async {
    if (task != backgroundSyncTask) return true;
    final db = AppDatabase();
    ConnectorHub? hub;
    try {
      hub = await ConnectorHub.system(db);
      return await runConnectorSync(hub);
    } catch (_) {
      return true;
    } finally {
      await hub?.dispose();
      await db.close();
    }
  });
}

/// Registers the periodic job (Android only, safe to call on every launch:
/// the policy keeps one job). A failure to schedule is never fatal.
Future<void> scheduleBackgroundSync() async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    await Workmanager().initialize(connectorSyncDispatcher);
    await Workmanager().registerPeriodicTask(
      backgroundSyncUniqueName,
      backgroundSyncTask,
      frequency: backgroundSyncEvery,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(
        networkType: NetworkType.notRequired,
        requiresBatteryNotLow: true,
      ),
    );
  } catch (_) {
    // Foreground syncs still work; the job is a convenience.
  }
}

/// Removes the periodic job (when the last connector is revoked).
Future<void> cancelBackgroundSync() async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    await Workmanager().cancelByUniqueName(backgroundSyncUniqueName);
  } catch (_) {}
}
