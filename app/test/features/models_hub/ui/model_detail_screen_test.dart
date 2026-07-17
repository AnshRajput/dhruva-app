// Model detail screen (reworked): the PRIMARY flow is one prominent
// "Recommended download" card (device-appropriate default quant + verdict +
// one big Download button); the full per-quant list lives in a COLLAPSED
// "All quantizations (advanced)" section. License/gated status is still shown
// first, and a gated repo blocks the download affordance with an explanation.
// AppTheme.dark is supplied — the verdict chip / "May be slow" note need
// DhruvaTokens.

import 'dart:convert';
import 'dart:io';

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/downloads/download_manager.dart';
import 'package:dhruva/data/downloads/fake_download_backend.dart';
import 'package:dhruva/features/models_hub/state/downloads_controller.dart';
import 'package:dhruva/features/models_hub/ui/model_detail_screen.dart';
import 'package:drift/native.dart';
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

/// The download button watches `downloadsControllerProvider` for the real
/// per-task progress ring — stub it empty so these tests don't pull the real
/// download manager (path_provider + background_downloader) into a headless
/// run.
class _EmptyDownloadsController extends DownloadsController {
  @override
  Future<Map<String, DownloadProgress>> build() async => const {};
}

Future<void> _pump(
  WidgetTester tester, {
  required String repoId,
  required http.Response Function(http.Request) responder,
}) async {
  final client = mockHfClient(
    MockClient((request) async => responder(request)),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hfApiClientProvider.overrideWithValue(client),
        deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
        downloadsControllerProvider.overrideWith(_EmptyDownloadsController.new),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: ModelDetailScreen(repoId: repoId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'gated repo shows license + gated badge and blocks download (no button, '
    'and expanding the advanced list still blocks each quant)',
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

      // License is shown first (Rule: user sees license before any download).
      expect(find.text('llama2'), findsOneWidget);
      expect(find.textContaining('Gated · manual approval'), findsOneWidget);
      expect(
        find.textContaining("doesn't support Hugging Face sign-in yet"),
        findsOneWidget,
      );

      // No recommended download card for a gated repo, and no Download button
      // anywhere.
      expect(find.text('Recommended download'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Download'), findsNothing);

      // The advanced list is still offered (collapsed); expanding it shows the
      // per-quant blocking explanation instead of a working button.
      expect(find.text('All quantizations (advanced)'), findsOneWidget);
      await tester.tap(find.text('All quantizations (advanced)'));
      await tester.pumpAndSettle();
      expect(
        find.text('Requires Hugging Face sign-in — not supported yet'),
        findsWidgets,
      );
      expect(find.widgetWithText(FilledButton, 'Download'), findsNothing);
    },
  );

  testWidgets(
    'open repo leads with ONE recommended Download; the full quant list is '
    'collapsed until expanded',
    (tester) async {
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

      // PRIMARY: exactly one recommended card + one big Download button while
      // the advanced list is collapsed (its buttons aren't built yet).
      expect(find.text('Recommended download'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Download'), findsOneWidget);
      expect(find.text('All quantizations (advanced)'), findsOneWidget);

      // SECONDARY: expand → the full per-quant list appears, so now there are
      // several Download buttons.
      await tester.tap(find.text('All quantizations (advanced)'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilledButton, 'Download').evaluate().length,
        greaterThan(1),
      );
    },
  );

  testWidgets(
    'the recommended Download sanitizes a path-traversal filename to a bare '
    'basename before it reaches the download layer (attack #7: proves the UI '
    'call site DOES sanitize — see download_manager_test.dart for the shared '
    "boundary's own guard)",
    (tester) async {
      final maliciousTree = jsonEncode([
        {
          'type': 'file',
          'path': '../../../../etc/evil-Q4_K_M.gguf',
          'size': 100,
        },
      ]);
      final client = mockHfClient(
        MockClient((request) async {
          if (request.url.path.endsWith('/tree/main')) {
            return http.Response(maliciousTree, 200);
          }
          return http.Response(_fixture('model_info_open.json'), 200);
        }),
      );
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final modelsDir = Directory.systemTemp.createTempSync(
        'dhruva_traversal_ui_test_',
      );
      addTearDown(() {
        if (modelsDir.existsSync()) modelsDir.deleteSync(recursive: true);
      });
      final backend = FakeDownloadBackend();
      final manager = DownloadManager(
        backend: backend,
        db: db,
        modelsDirectory: modelsDir,
      );
      addTearDown(manager.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hfApiClientProvider.overrideWithValue(client),
            deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
            downloadManagerProvider.overrideWith((ref) async => manager),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const ModelDetailScreen(repoId: 'evil/repo'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The recommended card's single Download button is the primary CTA.
      expect(find.text('Recommended download'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Download'));
      // The tile shows an indeterminate progress ring after enqueue, so
      // pumpAndSettle would hang — pump a bounded number of frames instead.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(backend.enqueuedRequests, hasLength(1));
      final enqueued = backend.enqueuedRequests.values.single;
      expect(enqueued.fileName, 'evil-Q4_K_M.gguf'); // basename only
      expect(enqueued.fileName, isNot(contains('..')));
      expect(enqueued.fileName, isNot(contains('/')));
    },
  );
}
