/// Whether at least one inbox source is connected (Gmail, or the Android
/// notification digest). The Inbox tab is shown only when this is true; until
/// then Today carries a "Set up your inbox" card (spec B2: iOS without Gmail
/// must never see an empty Inbox tab).
///
/// Derived from the connector list: true when an inbox source is
/// connected. While the list is still loading, or if it cannot load, the Inbox
/// stays hidden rather than flashing an empty tab.
library;

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/connectors/connector.dart';
import '../../data/connectors/gmail_system_source.dart' show GmailClientIds;
import '../di/connector_providers.dart';

final inboxAvailableProvider = Provider<bool>((ref) {
  final entries = ref.watch(connectorListProvider).value ?? const [];
  return entries.any(
    (e) =>
        ConnectorIds.inboxSources.contains(e.connector.id) &&
        e.status.isConnected,
  );
});

/// Whether an inbox source COULD be set up on [platform]: Android always has the
/// notification digest; any platform with Gmail configured (OAuth client ids in
/// this build, see `GmailClientIds`) has Gmail. Without either, Today must not
/// offer to "set up your inbox": the card would lead nowhere.
bool inboxSetupPossibleOn(
  TargetPlatform platform, {
  GmailClientIds gmailIds = GmailClientIds.fromEnvironment,
}) => platform == TargetPlatform.android || gmailIds.supportedOn(platform);
