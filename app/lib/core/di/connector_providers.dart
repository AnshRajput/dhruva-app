/// Riverpod surface of the connectors data layer (Wave 2A). The UI waves read
/// these; nothing here builds a screen.
///
/// Tests override [connectorHubProvider] with a hub built from fakes
/// (`ConnectorHub.fromSources`) and `appDatabaseProvider` with an in-memory DB.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/connectors/connector.dart';
import '../../data/connectors/connector_hub.dart';
import '../../data/connectors/connector_sources.dart';
import '../../data/connectors/connector_store.dart';
import '../../data/connectors/notification_connector.dart';
import '../../data/connectors/search_index.dart';
import '../../data/connectors/system_sources.dart';
import '../settings/prefs_store.dart';
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
final connectorHubProvider = FutureProvider<ConnectorHub>(
  (ref) async {
    final hub = await ConnectorHub.system(ref.watch(appDatabaseProvider));
    // Revoking a source deletes its data; the written brief quotes it, so the
    // cached brief goes too (even if Today is not on screen to notice).
    hub.onWiped = () async => (await ref.read(
      prefsStoreProvider.future,
    )).write(briefCachePrefsKey, '');
    ref.onDispose(() => unawaited(hub.dispose()));
    return hub;
  },
  // A hub that cannot start must surface as an error (the list then reads as
  // "no connectors" and Today says so), not retry forever behind a loading
  // state that never ends.
  retry: (_, _) => null,
);

/// Ids of the connectors whose OS access is on RIGHT NOW (statuses re-read
/// from the OS first). Ask uses this, like Today does, so a permission turned
/// off in system settings stops that source being retrieved and cited even
/// though its account row and stored items remain. A hub that cannot start
/// means nothing is connected. Not cached: every Ask turn asks again.
final liveConnectorIdsProvider = FutureProvider.autoDispose<Set<String>>((
  ref,
) async {
  final ConnectorHub hub;
  try {
    hub = await ref.watch(connectorHubProvider.future);
  } catch (_) {
    return const {};
  }
  await Future.wait(hub.all.map((c) => c.refreshStatus()));
  return {
    for (final c in hub.all)
      if (c.currentStatus.isConnected) c.id,
  };
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
  final ConnectorHub hub;
  try {
    hub = await ref.watch(connectorHubProvider.future);
  } catch (_) {
    // The hub failed to start, or was disposed while still loading (app
    // shutdown, a torn-down widget tree). No connectors is the honest
    // answer; callers already treat an empty list as "nothing connected".
    yield const [];
    return;
  }
  List<ConnectorEntry> snapshot() => [
    for (final c in hub.all)
      if (c.currentStatus.state != ConnectorState.unsupported)
        ConnectorEntry(c, c.currentStatus),
  ];
  final controller = StreamController<List<ConnectorEntry>>();
  // No snapshot until every status has been re-read from the OS: a half
  // refreshed list (one connector still at its initial "not connected") would
  // read as a disconnect and wipe derived data such as the written brief.
  var ready = false;
  final subs = [
    for (final c in hub.all)
      c.status.listen((_) {
        if (ready && !controller.isClosed) controller.add(snapshot());
      }),
  ];
  ref.onDispose(() {
    for (final s in subs) {
      unawaited(s.cancel());
    }
    unawaited(controller.close());
  });
  await Future.wait(hub.all.map((c) => c.refreshStatus()));
  ready = true;
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

/// Opt-in rows with their small per-connector settings (the folder's file
/// total, the notification apps the user excluded).
final connectorAccountsProvider = StreamProvider<List<ConnectorAccount>>((ref) {
  return ref.watch(connectorStoreProvider).watchAccounts();
});

/// Every indexed file of the connected folder (Library folder block).
final folderFilesProvider = StreamProvider<List<FolderFile>>((ref) {
  return ref.watch(connectorStoreProvider).watchFolderFiles();
});

/// Captured notifications of the last week, newest first (Inbox rows).
final inboxNotificationsProvider = StreamProvider<List<ConnectorItem>>((ref) {
  final store = ref.watch(connectorStoreProvider);
  return store.watchNotifications(
    since: store.now.subtract(notificationRetention),
  );
});

/// Opens a folder file in the OS viewer / launches a source app. Tests
/// override it.
final externalOpenerProvider = Provider<ExternalOpener>(
  (ref) => SystemExternalOpener(ConnectorsChannel()),
);

/// While watched (the app root does), refreshes every connector when the app
/// returns to the foreground: access granted or revoked in system settings
/// shows on the cards immediately, and the background job follows.
final connectorResumeProvider = Provider<void>((ref) {
  final observer = _ResumeObserver(() async {
    try {
      final hub = await ref.read(connectorHubProvider.future);
      await hub.onResume();
    } catch (_) {
      // No hub, no refresh; the next launch retries.
    }
  });
  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));
});

class _ResumeObserver with WidgetsBindingObserver {
  _ResumeObserver(this._onResume);
  final Future<void> Function() _onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_onResume());
  }
}

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
