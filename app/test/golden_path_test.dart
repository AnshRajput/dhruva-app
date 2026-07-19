// GOLDEN PATH E2E: the one flow the whole product exists for — a fresh user
// installs a model and gets a real streamed answer, with zero cloud calls.
//
// This boots the REAL DhruvaApp (real router, providers, screens, chat
// controller, download pipeline) and fakes only what can't run in a test:
// the native inference engine (FakeEngineService), the download backend
// (FakeDownloadBackend), the DB (in-memory), and device info. Everything the
// user actually touches — the download-to-installed reconciliation and the
// chat send → token stream → rendered bubble — is the production code.
//
// It lives in test/ (not integration_test/) so the standard gate — `make
// verify` / `flutter test` — actually runs it as a regression guard. It uses
// the standard test binding, so it's deterministic and needs no device.

import 'dart:io';

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/router/app_router.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/downloads/download_backend.dart';
import 'package:dhruva/data/downloads/download_manager.dart';
import 'package:dhruva/data/downloads/fake_download_backend.dart';
import 'package:dhruva/data/downloads/storage_manager.dart';
import 'package:dhruva/engine_bindings/fake_engine_service.dart';
import 'package:dhruva/features/chat/state/installed_models_provider.dart'
    as chat_installed;
import 'package:dhruva/main.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/mock_hf_client.dart';

const _fakeDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

void main() {
  late AppDatabase db;
  late Directory modelsDir;
  late FakeDownloadBackend backend;
  late DownloadManager manager;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    modelsDir = Directory.systemTemp.createTempSync('dhruva_golden_path_');
    backend = FakeDownloadBackend();
    manager = DownloadManager(
      backend: backend,
      db: db,
      modelsDirectory: modelsDir,
    );
    // Start every run at chat — this global router persists across the suite.
    appRouter.go('/chat');
  });

  tearDown(() async {
    await manager.dispose();
    await db.close();
    if (modelsDir.existsSync()) modelsDir.deleteSync(recursive: true);
  });

  final request = DownloadRequest(
    repoId: 'bartowski/Llama-3.2-1B-Instruct-GGUF',
    fileName: 'Llama-3.2-1B-Instruct-Q4_K_M.gguf',
    url: Uri.parse('https://huggingface.co/x/resolve/main/x.gguf'),
    expectedSizeBytes: 5,
  );

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          engineServiceProvider.overrideWithValue(FakeEngineService()),
          downloadManagerProvider.overrideWith((ref) async => manager),
          appDatabaseProvider.overrideWithValue(db),
          modelsDirectoryProvider.overrideWith((ref) async => modelsDir),
          deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
          hfApiClientProvider.overrideWithValue(
            mockHfClient(
              MockClient((request) async => http.Response('[]', 200)),
            ),
          ),
        ],
        child: const DhruvaApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(DhruvaApp)),
        listen: false,
      );

  Future<void> emitAndSettle(WidgetTester tester, BackendUpdate update) async {
    await tester.runAsync(() async {
      backend.emit(update);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a fresh user downloads a model and gets a streamed, on-device answer',
    (tester) async {
      await pumpApp(tester);
      final container = containerOf(tester);

      // 1) Fresh install: nothing is installed yet. Hold the chat picker's
      //    installed-model list alive across the download like a screen would.
      container.listen(chat_installed.installedModelsProvider, (_, _) {});
      await tester.runAsync(() async {
        expect(
          await container.read(chat_installed.installedModelsProvider.future),
          isEmpty,
        );
      });

      // 2) Drive the REAL download pipeline to completion.
      await tester.runAsync(() => manager.enqueue(request, freeBytes: 1 << 30));
      await tester.pumpAndSettle();
      await emitAndSettle(
        tester,
        BackendProgressUpdate(
          request.taskId,
          progress: 0.5,
          expectedFileSizeBytes: request.expectedSizeBytes,
        ),
      );
      final file = File('${modelsDir.path}/${request.fileName}')
        ..writeAsBytesSync([1, 2, 3, 4, 5]);
      backend.filePaths[request.taskId] = file.path;
      await emitAndSettle(
        tester,
        BackendStatusUpdate(request.taskId, status: BackendTaskStatus.complete),
      );

      // 3) The model is now installed and visible to chat with no restart.
      late final List<InstalledModelInfo> installed;
      await tester.runAsync(() async {
        installed = await container.read(
          chat_installed.installedModelsProvider.future,
        );
      });
      expect(installed.map((m) => m.repoId), contains(request.repoId));
      final modelId = installed
          .firstWhere((m) => m.repoId == request.repoId)
          .id;

      // 4) Open a fresh chat with that model (the same int-`extra` hand-off the
      //    model-picker flow uses — app_router.dart).
      appRouter.go('/chat/new', extra: modelId);
      await tester.pumpAndSettle();

      // The composer is live, the friendly model name shows, and the empty
      // chat offers the golden-path suggested prompts.
      expect(find.text('Message Dhruva…'), findsOneWidget);
      expect(find.text('Llama-3.2-1B-Instruct'), findsOneWidget);
      const prompt = 'Write a haiku about the ocean.';
      expect(find.text(prompt), findsOneWidget);

      // 5) Tap a suggested prompt (PRD golden path) and watch the on-device
      //    engine stream a reply into the thread.
      await tester.tap(find.text(prompt));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // The user's turn and the streamed assistant answer both rendered.
      expect(find.text(prompt), findsOneWidget);
      expect(find.textContaining('Hello world!'), findsOneWidget);

      // Let the "ready — start chatting" snackbar timer expire cleanly.
      await tester.pump(const Duration(seconds: 5));
    },
  );
}
