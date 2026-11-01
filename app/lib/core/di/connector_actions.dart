/// The one tap that turns a connector on, shared by Today's "Connect your
/// calendar" card and onboarding's "Allow calendar access": ask the OS, then
/// read what is there so the first screen already has real data. The outcome
/// (granted, denied, needs attention) lands on the connector's status stream,
/// which every card already shows with its fix.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/connectors/connector.dart';
import 'connector_providers.dart';

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
