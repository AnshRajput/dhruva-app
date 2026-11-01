/// Riverpod surface of the connectors data layer (Wave 2A). The UI waves read
/// these; nothing here builds a screen.
///
/// Tests override [connectorHubProvider] with a hub built from fakes
/// (`ConnectorHub.fromSources`) and `appDatabaseProvider` with an in-memory DB.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/connectors/connector.dart';
import '../../data/connectors/connector_hub.dart';
import '../../data/connectors/connector_store.dart';
import '../../data/connectors/search_index.dart';
import 'providers.dart';

/// One row of the connector list: the connector and its latest status.
final class ConnectorEntry {
  final Connector connector;
  final ConnectorStatus status;
  const ConnectorEntry(this.connector, this.status);
}

/// Store access (accounts, items, ledger). Stateless over the app database.
final connectorStoreProvider = Provider<ConnectorStore>((ref) {
  return ConnectorStore(db: ref.watch(appDatabaseProvider));
});

/// The four connectors + sync service over the real OS sources.
final connectorHubProvider = FutureProvider<ConnectorHub>((ref) async {
  final hub = await ConnectorHub.system(ref.watch(appDatabaseProvider));
  ref.onDispose(() => unawaited(hub.dispose()));
  return hub;
});

/// Keyword search over everything the connectors stored. The engine (FTS5, or
/// the BM25 fallback when SQLite lacks it) is chosen once, here.
final searchIndexProvider = FutureProvider<SearchIndex>((ref) {
  return openSearchIndex(
    ref.watch(appDatabaseProvider),
    ref.watch(connectorStoreProvider),
  );
});

/// Connectors the platform supports, each with its live status. Statuses are
/// re-read from the OS first, so a permission switched off in system settings
/// shows up the next time this provider is built.
final connectorListProvider = StreamProvider<List<ConnectorEntry>>((
  ref,
) async* {
  final hub = await ref.watch(connectorHubProvider.future);
  List<ConnectorEntry> snapshot() => [
    for (final c in hub.all)
      if (c.currentStatus.state != ConnectorState.unsupported)
        ConnectorEntry(c, c.currentStatus),
  ];
  final controller = StreamController<List<ConnectorEntry>>();
  final subs = [
    for (final c in hub.all)
      c.status.listen((_) {
        if (!controller.isClosed) controller.add(snapshot());
      }),
  ];
  ref.onDispose(() {
    for (final s in subs) {
      unawaited(s.cancel());
    }
    unawaited(controller.close());
  });
  await Future.wait(hub.all.map((c) => c.refreshStatus()));
  if (!controller.isClosed) controller.add(snapshot());
  yield* controller.stream;
});

/// Events starting today (local day), earliest first.
final todaysEventsProvider = StreamProvider<List<ConnectorItem>>((ref) {
  final store = ref.watch(connectorStoreProvider);
  return store.watchTodaysEvents(store.now);
});

/// The next two events from now.
final nextEventsProvider = StreamProvider<List<ConnectorItem>>((ref) {
  final store = ref.watch(connectorStoreProvider);
  return store.watchNextEvents(store.now);
});

/// Captured notifications (last 7 days) grouped by app, newest app first.
final notificationGroupsProvider = StreamProvider<List<NotificationGroup>>((
  ref,
) {
  return ref.watch(connectorStoreProvider).watchNotificationsByApp();
});

/// The privacy ledger, newest first.
final ledgerProvider = StreamProvider<List<LedgerEntry>>((ref) {
  return ref.watch(connectorStoreProvider).watchLedger();
});

/// A search request. Value-equal so Riverpod caches identical queries.
final class ConnectorSearchQuery {
  final String text;
  final Set<String> sources;
  final Set<ItemKind> kinds;
  final int limit;
  ConnectorSearchQuery(
    this.text, {
    this.sources = const {},
    this.kinds = const {},
    this.limit = 20,
  });

  @override
  bool operator ==(Object other) =>
      other is ConnectorSearchQuery &&
      other.text == text &&
      other.limit == limit &&
      other.sources.length == sources.length &&
      other.sources.containsAll(sources) &&
      other.kinds.length == kinds.length &&
      other.kinds.containsAll(kinds);

  @override
  int get hashCode => Object.hash(
    text,
    limit,
    Object.hashAllUnordered(sources),
    Object.hashAllUnordered(kinds),
  );
}

final connectorSearchProvider =
    FutureProvider.family<List<SearchHit>, ConnectorSearchQuery>((
      ref,
      q,
    ) async {
      final index = await ref.watch(searchIndexProvider.future);
      return index.search(
        q.text,
        limit: q.limit,
        sources: q.sources.isEmpty ? null : q.sources,
        kinds: q.kinds.isEmpty ? null : q.kinds,
      );
    });

/// App-open work: pick the search engine, refresh every status, sync what is
/// stale and (Android) make sure the periodic background job exists. Started
/// once from `main()`; errors never block launch.
final connectorBootstrapProvider = FutureProvider<void>((ref) async {
  final hub = await ref.watch(connectorHubProvider.future);
  await ref.read(searchIndexProvider.future);
  await hub.sync.syncOnOpen();
  await hub.syncBackgroundJob();
});
