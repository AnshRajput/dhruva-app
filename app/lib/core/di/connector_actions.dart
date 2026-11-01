/// The one tap that turns a connector on, shared by Today's "Connect your
/// calendar" card and onboarding's "Allow calendar access": ask the OS, then
/// read what is there so the first screen already has real data. The outcome
/// (granted, denied, needs attention) lands on the connector's status stream,
/// which every card already shows with its fix.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/connectors/connector.dart';
import 'connector_providers.dart';

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
