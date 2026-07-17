// Model detail screen: license/gated status is shown, and a gated repo
// blocks the download affordance with an explanation instead of a broken
// download button (T5 test requirement, Rule: user sees license first).

import 'dart:io';

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/data/hf_api/hf_api_client.dart';
import 'package:dhruva/features/models_hub/ui/model_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _fixture(String name) =>
    File('test/data/hf_api/fixtures/$name').readAsStringSync();

const _fakeDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

Future<void> _pump(
  WidgetTester tester, {
  required String repoId,
  required http.Response Function(http.Request) responder,
}) async {
  final client = HfApiClient(
    client: MockClient((request) async => responder(request)),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hfApiClientProvider.overrideWithValue(client),
        deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
      ],
      child: MaterialApp(home: ModelDetailScreen(repoId: repoId)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'gated repo shows license + gated badge and blocks the download button',
    (tester) async {
      await _pump(
        tester,
        repoId: 'meta-llama/Llama-2-7b-hf',
        responder: (request) {
          if (request.url.path.endsWith('/tree/main')) {
            return http.Response(_fixture('repo_tree.json'), 200);
          }
          if (request.url.path.endsWith('/mmproj')) {
            return http.Response(_fixture('mmproj_tree.json'), 200);
          }
          return http.Response(_fixture('model_info_gated.json'), 200);
        },
      );

      // License is shown (Rule: user sees license first).
      expect(find.text('llama2'), findsOneWidget);
      expect(find.textContaining('Gated · manual approval'), findsOneWidget);
      expect(
        find.textContaining("doesn't support Hugging Face sign-in yet"),
        findsOneWidget,
      );

      // No functional download button for a gated repo.
      expect(find.widgetWithText(FilledButton, 'Download'), findsNothing);
      expect(
        find.text('Requires Hugging Face sign-in — not supported yet'),
        findsWidgets,
      );
    },
  );

  testWidgets('open repo shows an enabled Download button per quant file', (
    tester,
  ) async {
    await _pump(
      tester,
      repoId: 'bartowski/Qwen2.5-1.5B-Instruct-GGUF',
      responder: (request) {
        if (request.url.path.endsWith('/tree/main')) {
          return http.Response(_fixture('repo_tree.json'), 200);
        }
        if (request.url.path.endsWith('/mmproj')) {
          return http.Response(_fixture('mmproj_tree.json'), 200);
        }
        return http.Response(_fixture('model_info_open.json'), 200);
      },
    );

    expect(find.text('apache-2.0'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Download'), findsWidgets);
  });
}
