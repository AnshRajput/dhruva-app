// App-shell smoke test: `/today` is home (daily-assistant redesign), Ask is the
// old Chat tab, and `/settings/models` is reachable via Today's gear. `debug_chat` (Loop 2/3's
// dev harness) was deleted in Loop 4 and no longer has a route.

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/router/app_router.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/mock_hf_client.dart';

void main() {
  // appRouter is a process-wide singleton: start every test on Today.
  setUp(() => appRouter.go('/today'));

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hfApiClientProvider.overrideWithValue(
            mockHfClient(
              MockClient((request) async => http.Response('[]', 200)),
            ),
          ),
          deviceInfoServiceProvider.overrideWithValue(
            const FakeDeviceInfoService(
              memory: DeviceMemoryInfo(
                totalBytes: 8000000000,
                availableBytes: 4000000000,
              ),
              storage: DeviceStorageInfo(
                totalBytes: 64000000000,
                freeBytes: 32000000000,
              ),
            ),
          ),
          // `/chat` (Loop 4 home) touches `chatRepositoryProvider` on its
          // very first frame, unlike the old `/models` home whose first tab
          // never queried the db — the real `AppDatabase()` resolves its
          // file path via `path_provider`, a platform channel `flutter
          // test` doesn't have, so it never settles. In-memory swaps that
          // out for a real, hermetic drift database.
          appDatabaseProvider.overrideWithValue(
            AppDatabase(NativeDatabase.memory()),
          ),
        ],
        child: const DhruvaApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Today is the app home with Today / Ask / Library tabs (no Inbox)',
    (tester) async {
      await pumpApp(tester);

      expect(find.text('Your brief'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Today'),
        ),
        findsOneWidget,
      );
      expect(find.text('Ask'), findsOneWidget);
      expect(find.text('Library'), findsOneWidget);
      // Inbox tab stays hidden until an inbox source exists.
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Inbox'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('Ask tab shows the conversation list (formerly Chat)', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Personas'), findsOneWidget);
    expect(find.byTooltip('Actions'), findsOneWidget);
  });

  testWidgets('models hub is reachable from Today > Settings > Models', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const ValueKey('today-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-models')));
    await tester.pumpAndSettle();

    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('Installed'), findsOneWidget);
  });
}
