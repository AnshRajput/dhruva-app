// Shared harness for tests that drive the real `DhruvaApp` + `appRouter`
// singleton (shell, redirects, placeholder surfaces, appearance).

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/connector_providers.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/router/app_router.dart';
import 'package:dhruva/core/settings/prefs_store.dart';
import 'package:dhruva/data/characters/character_repository.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/features/today/state/today_data.dart';
import 'package:dhruva/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'mock_hf_client.dart';

const harnessDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

/// Pumps the whole app on [location] with an in-memory DB and prefs.
///
/// [prefs] defaults to a store where the "what moved" sheet is already
/// dismissed, so tests not about that sheet are not blocked by it.
Future<AppDatabase> pumpDhruvaApp(
  WidgetTester tester, {
  String location = '/today',
  PrefsStore? prefs,
  List<Override> overrides = const [],
  // Wide enough for flutter_test's Ahem font (much wider than Manrope).
  Size surface = const Size(800, 2400),
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  appRouter.go(location);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        // The real asset loader never completes under fake async, and the
        // personas list now awaits seeding.
        characterRepositoryProvider.overrideWithValue(
          CharacterRepository(db: db, starterPackLoader: () async => null),
        ),
        deviceInfoServiceProvider.overrideWithValue(harnessDeviceInfo),
        prefsStoreProvider.overrideWith(
          (ref) async =>
              prefs ?? MemoryPrefsStore({'what_moved_dismissed': 'true'}),
        ),
        // Drift live queries leave a zero-length timer when disposed, which
        // fails a widget test; Today's streams read as empty here (the Today
        // tests use the real store, see test/features/today).
        // No OS connectors in app-level tests: nothing is connected.
        connectorListProvider.overrideWith(
          (ref) => Stream.value(const <ConnectorEntry>[]),
        ),
        todayEventsProvider.overrideWith((ref) => Stream.value(const [])),
        upNextEventsProvider.overrideWith((ref) => Stream.value(const [])),
        notificationGroupsProvider.overrideWith(
          (ref) => Stream.value(const []),
        ),
        hfApiClientProvider.overrideWithValue(
          mockHfClient(MockClient((r) async => http.Response('[]', 200))),
        ),
        ...overrides,
      ],
      child: const DhruvaApp(),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }
  return db;
}
