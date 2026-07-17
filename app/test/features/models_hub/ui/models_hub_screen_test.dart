// Search tab: happy path renders results, offline surfaces the typed
// NetworkOfflineFailure message (T5 test requirement).

import 'dart:io';

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/hf_api/hf_api_client.dart';
import 'package:dhruva/features/models_hub/ui/models_hub_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../../support/mock_hf_client.dart';

String _fixture(String name) =>
    File('test/data/hf_api/fixtures/$name').readAsStringSync();

const _fakeDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

Future<void> _pump(WidgetTester tester, HfApiClient client) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hfApiClientProvider.overrideWithValue(client),
        deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
      ],
      child: MaterialApp(theme: AppTheme.dark, home: const ModelsHubScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'search happy path renders results from the real response shape',
    (tester) async {
      final client = mockHfClient(
        MockClient(
          (request) async => http.Response(_fixture('search_gguf.json'), 200),
        ),
      );
      await _pump(tester, client);

      expect(
        find.text('HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive'),
        findsOneWidget,
      );
      expect(find.text('unsloth/Qwen3.6-27B-MTP-GGUF'), findsOneWidget);
      expect(find.text('apache-2.0'), findsWidgets);
    },
  );

  testWidgets('offline search shows the typed offline message', (tester) async {
    final client = mockHfClient(
      MockClient((request) async {
        throw const SocketException('no route to host');
      }),
    );
    await _pump(tester, client);

    expect(
      find.text("You're offline — check your connection and try again."),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets(
    // QA (Loop-4 attack list #6): Amendment 4c's rail is only meant above an
    // *unfiltered* view.
    'the recommended rail is visible with an empty query and disappears '
    'once the user submits a search query',
    (tester) async {
      final client = mockHfClient(
        MockClient(
          (request) async => http.Response(_fixture('search_gguf.json'), 200),
        ),
      );
      await _pump(tester, client);

      expect(find.text('Recommended for your device'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'llama');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.text('Recommended for your device'), findsNothing);
    },
  );
}
