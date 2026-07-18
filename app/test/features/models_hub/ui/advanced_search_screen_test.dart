// WS1: the demoted "Search all of Hugging Face (advanced)" screen. Happy path
// renders results, offline surfaces the typed failure, and results are
// STRICTLY filtered to phone-runnable (≤ ~4B) GGUF — a huge model in the
// response never reaches the list.

import 'dart:convert';
import 'dart:io';

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/hf_api/hf_api_client.dart';
import 'package:dhruva/features/models_hub/ui/advanced_search_screen.dart';
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
      child: MaterialApp(
        theme: AppTheme.dark,
        home: const AdvancedSearchScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('happy path renders phone-runnable results', (tester) async {
    final client = mockHfClient(
      MockClient(
        (request) async => http.Response(_fixture('search_mobile.json'), 200),
      ),
    );
    await _pump(tester, client);

    expect(find.text('bartowski/Llama-3.2-1B-Instruct-GGUF'), findsOneWidget);
    expect(find.textContaining('Fit for your phone'), findsWidgets);
  });

  testWidgets('strictly filters out non-mobile (> ~4B) models', (tester) async {
    final client = mockHfClient(
      MockClient(
        (request) async => http.Response(
          jsonEncode([
            {'id': 'org/Giant-70B-GGUF', 'downloads': 9999, 'tags': <String>[]},
            {'id': 'org/Tiny-1B-GGUF', 'downloads': 10, 'tags': <String>[]},
          ]),
          200,
        ),
      ),
    );
    await _pump(tester, client);

    expect(find.text('org/Tiny-1B-GGUF'), findsOneWidget);
    // The 70B firehose row is filtered out — never shown on the advanced path.
    expect(find.text('org/Giant-70B-GGUF'), findsNothing);
  });

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
}
