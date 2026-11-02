/// The user-tapped actions on connectors, in one place so Settings, Library
/// and Inbox cannot drift apart: connect, disconnect (wipe the local copy and,
/// if asked, open the OS page that revokes the grant), re-index the folder,
/// choose which notification apps to skip.
///
/// Every action goes through the hub, which keeps the background job in step
/// (`ConnectorHub.syncBackgroundJob` runs after each connect/revoke).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/connectors/connector.dart';
import '../../data/connectors/connector_hub.dart';
import 'connector_providers.dart';

final class ConnectorActions {
  ConnectorActions(this._ref);
  final Ref _ref;

  Future<ConnectorHub> get _hub => _ref.read(connectorHubProvider.future);

  Future<Connector?> _connector(String id) async => (await _hub).byId(id);

  /// Asks the OS for what [id] needs. Ends in the connector's new status
  /// (also streamed to the cards); never throws for a user "no".
  Future<ConnectorStatus> connect(String id) async {
    final c = await _connector(id);
    if (c == null) return ConnectorStatus.unsupported;
    final changed = await c.connect();
    // First read right away, so Today and the Library have something to show.
    // Not after backing out of a picker: nothing was connected just now.
    if (changed && c.currentStatus.isConnected) {
      unawaited(_firstSync(c));
    }
    // A refresh after the prompt may have replaced the status: the answer to
    // this tap is what connect() itself ended in.
    return changed && !c.currentStatus.isConnected
        ? c.lastConnectStatus
        : c.currentStatus;
  }

  Future<void> _firstSync(Connector c) async {
    try {
      await c.sync();
    } catch (_) {
      // The card shows what is wrong.
    }
  }

  /// Pull-to-refresh: reads every connected source now, ignoring the 10-minute
  /// app-open throttle. Never throws; each card shows its own failure.
  Future<void> refreshAll() async {
    try {
      await (await _hub).sync.refresh();
    } catch (_) {
      // No hub, nothing to refresh.
    }
  }

  /// Moves queued notifications into the Inbox right now (Inbox opened).
  Future<void> drainNotifications() async {
    try {
      await (await _hub).sync.drainNotifications();
    } catch (_) {
      // No hub, nothing to drain.
    }
  }

  /// Deletes the local copy of [id] (items, index, content ledger rows) and
  /// stops reading. With [openSystemSettings] it then opens the OS page where
  /// the user can switch the permission off too (an app cannot do that itself).
  Future<void> disconnect(String id, {bool openSystemSettings = false}) async {
    final c = await _connector(id);
    if (c == null) return;
    await c.revoke();
    if (openSystemSettings) await c.openSystemSettings();
  }

  Future<void> openSystemSettings(String id) async =>
      (await _connector(id))?.openSystemSettings();

  /// Opens the OS folder picker; picking a different folder replaces the old
  /// grant (the connector releases it).
  Future<ConnectorStatus> chooseFolder() => connect(ConnectorIds.folder);

  /// The explicit "Index now": runs to the end or until [cancelIndex].
  /// Returns what it did, or throws a [ConnectorException] naming the fix.
  Future<SyncResult> indexFolder() async => (await _hub).folder.indexNow();

  Future<void> cancelIndex() async => (await _hub).folder.cancelSync();

  /// Notification apps (package names) the listener must ignore.
  Future<void> setExcludedApps(List<String> packages) async =>
      (await _hub).notifications.setExcludedApps(packages);
}

final connectorActionsProvider = Provider<ConnectorActions>(
  ConnectorActions.new,
);

/// The app came back to the foreground (maybe from system settings): re-read
/// every connector's status from the OS. A Calendar that was denied in-app and
/// is now allowed connects and syncs on the spot (no prompt: the OS already
/// said yes). Returns true when Calendar went from denied to connected, so a
/// caller waiting on it (onboarding) can move on.
Future<bool> resumeConnectors(WidgetRef ref) async {
  try {
    final hub = await ref.read(connectorHubProvider.future);
    final cal = hub.byId(ConnectorIds.calendar);
    final wasDenied =
        cal?.currentStatus.state == ConnectorState.permissionDenied;
    await Future.wait(hub.all.map((c) => c.refreshStatus()));
    if (wasDenied &&
        cal != null &&
        cal.currentStatus.state == ConnectorState.notConnected) {
      return (await connectAndSync(ref, ConnectorIds.calendar))?.isConnected ??
          false;
    }
    return false;
  } on Object {
    return false;
  }
}

/// Runs `connect()` on connector [id] and, when it ended connected, syncs.
/// Returns the status afterwards, or null if the connectors could not start
/// at all (the caller says "try again").
Future<ConnectorStatus?> connectAndSync(WidgetRef ref, String id) async {
  try {
    final hub = await ref.read(connectorHubProvider.future);
    final c = hub.byId(id);
    if (c == null) return null;
    await c.connect();
    final status = c.currentStatus;
    if (status.isConnected) {
      try {
        await hub.sync.refresh();
      } on Object {
        // The sync reports its own failure on the status stream.
      }
    }
    return status;
  } on Object {
    return null;
  }
}
