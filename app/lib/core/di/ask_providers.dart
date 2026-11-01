/// Riverpod surface for "Ask grounded in your data" (Wave 3C). Reads the
/// connector providers (Wave 2A); builds no UI.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/connectors/ask_retrieval.dart';
import '../../data/connectors/connector.dart';
import 'connector_providers.dart';

/// Searches the connectors' items for an Ask question.
final askRetrieverProvider = FutureProvider<AskRetriever>((ref) async {
  return AskRetriever(
    index: await ref.watch(searchIndexProvider.future),
    store: ref.watch(connectorStoreProvider),
  );
});

/// Names of stored contacts, for Auto's "a known contact name" rule in the
/// live chip preview. Empty on any failure (the preview just shows less).
final askContactNamesProvider = FutureProvider.autoDispose<List<String>>((
  ref,
) async {
  try {
    return await ref.watch(connectorStoreProvider).contactNames();
  } on Object {
    return const [];
  }
});

/// For the "Search in" chips: connector id -> connected, for every connector
/// this platform offers. Mail is absent until a mail connector exists, which
/// is how Ask hides it. Empty while loading or if the hub failed.
final askConnectorsProvider = Provider<Map<String, bool>>((ref) {
  final entries = ref.watch(connectorListProvider).value ?? const [];
  return {
    for (final e in entries)
      e.connector.id:
          e.status.state == ConnectorState.connected ||
          e.status.state == ConnectorState.syncing,
  };
});
