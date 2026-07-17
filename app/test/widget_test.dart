// App-shell smoke test: `/chat` is home (Loop 4 — chat-spec.md §1), `/models`
// is reachable via the bottom nav (app_shell.dart). `debug_chat` (Loop 2/3's
// dev harness) was deleted in Loop 4 and no longer has a route.

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/main.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/mock_hf_client.dart';

void main() {
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

  testWidgets('chat is the app home, reached via the bottom nav', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('Chats'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Models'), findsOneWidget);
  });

  testWidgets('models hub is reachable from the bottom nav', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Models'));
    await tester.pumpAndSettle();

    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Installed'), findsOneWidget);
  });
}
