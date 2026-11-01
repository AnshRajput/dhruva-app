// Pumps one connector-backed screen (Connectors, Library, Inbox ...) over an
// in-memory DB and the fake connector sources, with a tiny router so `push`
// targets resolve. Records every location the screen navigates to.

import 'package:dhruva/core/di/connector_providers.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/settings/prefs_store.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/connectors/connector.dart';
import 'package:dhruva/data/connectors/connector_hub.dart';
import 'package:dhruva/data/connectors/connector_sources.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'app_harness.dart' show streamSafeTestDb;
import 'fake_connector_sources.dart';

class FakeOpener implements ExternalOpener {
  final opened = <(String, String)>[];
  final launched = <String>[];
  bool launchResult = true;
  OpenFailure? failure;

  @override
  Future<void> openFile(String grantId, String entryId) async {
    if (failure != null) throw failure!;
    opened.add((grantId, entryId));
  }

  @override
  Future<bool> launchApp(String package) async {
    launched.add(package);
    return launchResult;
  }
}

class ConnectorUi {
  ConnectorUi(this.db, this.kit, this.opener, this.visited, this.scheduler);
  final AppDatabase db;
  final ConnectorTestKit kit;
  final FakeOpener opener;
  final FakeScheduler scheduler;

  /// Every location the screen pushed (`/ask/new?focus=3`, ...).
  final List<String> visited;
}

/// Pumps [home] (at route `/home`) and returns the fakes. [clock] is the
/// connector clock; screens read `DateTime.now()` for relative times.
Future<ConnectorUi> pumpConnectorScreen(
  WidgetTester tester,
  Widget home, {
  DateTime Function()? clock,
  List<Override> overrides = const [],
  Size surface = const Size(800, 2400),
  bool notificationsSupported = true,

  /// Replaces the hub the providers see (e.g. one that never finishes
  /// starting, to show the loading state).
  Future<ConnectorHub>? hubFuture,
}) async {
  final scheduler = FakeScheduler();
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final db = streamSafeTestDb();
  addTearDown(db.close);
  final kit = ConnectorTestKit.create(
    db,
    clock: clock ?? DateTime.now,
    notificationsSupported: notificationsSupported,
    scheduler: scheduler,
  );
  addTearDown(kit.dispose);
  final opener = FakeOpener();
  final visited = <String>[];

  final router = GoRouter(
    initialLocation: '/home',
    routes: [GoRoute(path: '/home', builder: (_, _) => home)],
    // Every other location (the screen's push targets) lands here.
    errorBuilder: (context, state) {
      final at = state.uri.toString();
      if (visited.isEmpty || visited.last != at) visited.add(at);
      return Scaffold(body: Center(child: Text('at $at')));
    },
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        connectorHubProvider.overrideWith(
          (ref) => hubFuture ?? Future.value(kit.hub),
        ),
        externalOpenerProvider.overrideWithValue(opener),
        prefsStoreProvider.overrideWith((ref) async => MemoryPrefsStore()),
        ...overrides,
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return ConnectorUi(db, kit, opener, visited, scheduler);
}

/// Connects the folder connector over [ui] and fills its index directly (no
/// file IO, which cannot complete under the widget test clock). [total] is
/// what the last folder listing held (defaults to the files given).
Future<void> seedFolder(
  ConnectorUi ui,
  Map<String, String> files, {
  int? total,
  String grantId = 'tree:1',
  String name = 'Documents/Notes',
}) async {
  ui.kit.folder.nextPick = FolderGrant(id: grantId, name: name);
  await ui.kit.hub.folder.connect();
  final store = ui.kit.hub.store;
  await store.upsertItems(ConnectorIds.folder, [
    for (final e in files.entries)
      ItemDraft(
        externalId: 'doc:${e.key}',
        kind: ItemKind.file,
        title: e.key,
        body: e.value,
        sentAt: DateTime.now(),
        flags: {
          'fileId': 'doc:${e.key}',
          'mtime': 1,
          'size': e.value.length,
          'name': e.key,
          'mime': 'text/plain',
          'section': 1,
          'page': 1,
        },
      ),
  ]);
  await store.saveAccount(
    ConnectorIds.folder,
    config: {'grantId': grantId, 'name': name, 'total': total ?? files.length},
  );
}
