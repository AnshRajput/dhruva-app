// UX-hardening A1 (THE fix): the shipped app's #1 "downloaded a model but
// still can't start a convo" bug. Every read-only installed-model provider is
// a cached one-shot that was never invalidated when a download finished, so a
// freshly-downloaded model stayed invisible everywhere until an app restart.
// The always-mounted AppShell now listens on the DownloadManager progress
// (via downloadsControllerProvider) and invalidates all three on completion.
//
// This drives the REAL DownloadManager wired to a FakeDownloadBackend (same
// harness shape as app_shell_test.dart / downloads_screen_test.dart) through a
// full download-to-complete, then proves each installed-model provider reports
// the new model WITHOUT any manual invalidate/refresh/restart.

import 'dart:async';
import 'dart:io';

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/downloads/download_backend.dart';
import 'package:dhruva/data/downloads/download_manager.dart';
import 'package:dhruva/data/downloads/fake_download_backend.dart';
import 'package:dhruva/features/characters/state/installed_models_provider.dart'
    as char_installed;
import 'package:dhruva/features/chat/state/installed_models_provider.dart'
    as chat_installed;
import 'package:dhruva/features/models_hub/state/storage_controller.dart';
import 'package:dhruva/features/playground/state/playground_installed_models_provider.dart'
    as playground_installed;
import 'package:dhruva/main.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../../support/mock_hf_client.dart';

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
    modelsDir = Directory.systemTemp.createTempSync('dhruva_a1_refresh_test_');
    backend = FakeDownloadBackend();
    manager = DownloadManager(
      backend: backend,
      db: db,
      modelsDirectory: modelsDir,
    );
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
          downloadManagerProvider.overrideWith((ref) async => manager),
          appDatabaseProvider.overrideWithValue(db),
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

  Future<void> settleAfter(
    WidgetTester tester,
    FutureOr<void> Function() action,
  ) async {
    await action();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> emitAndSettle(WidgetTester tester, BackendUpdate update) async {
    await tester.runAsync(() async {
      backend.emit(update);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(DhruvaApp)),
        listen: false,
      );

  testWidgets(
    'a completed download makes the new model visible to the chat picker, the '
    'character picker AND the models-hub storage tab — no restart, no manual '
    'invalidate',
    (tester) async {
      await pumpApp(tester);
      final container = containerOf(tester);

      // Fresh install where the user already opened Chat: all three read-only
      // installed-model providers are primed and cached EMPTY.
      await tester.runAsync(() async {
        expect(
          await container.read(chat_installed.installedModelsProvider.future),
          isEmpty,
        );
        expect(
          await container.read(char_installed.installedModelsProvider.future),
          isEmpty,
        );
        expect(
          (await container.read(storageControllerProvider.future)).installed,
          isEmpty,
        );
        expect(
          await container.read(
            playground_installed.playgroundInstalledModelsProvider.future,
          ),
          isEmpty,
        );
      });
      // Hold them alive across the download, like a mounted screen would.
      container.listen(chat_installed.installedModelsProvider, (_, _) {});
      container.listen(char_installed.installedModelsProvider, (_, _) {});
      container.listen(
        playground_installed.playgroundInstalledModelsProvider,
        (_, _) {},
      );
      container.listen(storageControllerProvider, (_, _) {});

      // Real download → complete (writes the DB row, emits DownloadState.complete).
      await settleAfter(
        tester,
        () => manager.enqueue(request, freeBytes: 1 << 30),
      );
      await emitAndSettle(
        tester,
        BackendProgressUpdate(
          request.taskId,
          progress: 0.4,
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

      // The whole point: no one called invalidate/refresh, the app was never
      // restarted — yet every installed-model reader now sees the model.
      await tester.runAsync(() async {
        final chatModels = await container.read(
          chat_installed.installedModelsProvider.future,
        );
        final charModels = await container.read(
          char_installed.installedModelsProvider.future,
        );
        final storage = await container.read(storageControllerProvider.future);
        final playgroundModels = await container.read(
          playground_installed.playgroundInstalledModelsProvider.future,
        );
        expect(chatModels.map((m) => m.repoId), contains(request.repoId));
        expect(charModels.map((m) => m.repoId), contains(request.repoId));
        expect(playgroundModels.map((m) => m.repoId), contains(request.repoId));
        expect(
          storage.installed.map((m) => m.repoId),
          contains(request.repoId),
        );
      });

      // A5: the "X is ready — start chatting" SnackBar fired. Let it auto-dismiss
      // so its timer doesn't outlive the test.
      expect(find.textContaining('is ready — start chatting'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    },
  );
}
