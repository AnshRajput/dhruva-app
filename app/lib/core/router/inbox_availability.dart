/// Whether at least one inbox source is connected (Gmail, or the Android
/// notification digest). The Inbox tab is shown only when this is true; until
/// then Today carries a "Set up your inbox" card (spec B2: iOS without Gmail
/// must never see an empty Inbox tab).
///
/// Derived from the connector list: true when an inbox source (today only
/// notifications, which exists on Android alone; Gmail joins in 0.7b) is
/// connected. While the list is still loading, or if it cannot load, the Inbox
/// stays hidden rather than flashing an empty tab.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/connectors/connector.dart';
import '../di/connector_providers.dart';

final inboxAvailableProvider = Provider<bool>((ref) {
  final entries = ref.watch(connectorListProvider).value ?? const [];
  return entries.any(
    (e) =>
        ConnectorIds.inboxSources.contains(e.connector.id) &&
        e.status.isConnected,
  );
});
