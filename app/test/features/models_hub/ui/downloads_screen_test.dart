// Downloads screen: active task progress renders from the manager's
// progress stream, and Cancel calls through to the backend + drops the row
// (T5 test requirement).

import 'dart:async';
import 'dart:io';

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/downloads/download_backend.dart';
import 'package:dhruva/data/downloads/download_manager.dart';
import 'package:dhruva/data/downloads/fake_download_backend.dart';
import 'package:dhruva/features/models_hub/ui/downloads_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../../../support/mock_hf_client.dart';

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
    modelsDir = Directory.systemTemp.createTempSync('dhruva_dl_widget_test_');
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
    expectedSizeBytes: 1000,
  );
  // WS4: the download rows show the curated friendly name, not the raw repo id
  // or .gguf filename — this repoId is in the starter catalog.
  const friendlyName = 'Llama 3.2 1B Instruct';

  Future<void> pump(WidgetTester tester) async {
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
        child: MaterialApp(theme: AppTheme.dark, home: const DownloadsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Repeated pump() drains a plain provider-state change fine (see the
  // cancel test below), but `backend.emit` routes through TWO chained
  // `StreamController`s (`FakeDownloadBackend.updates` ->
  // `DownloadManager`'s internal subscription -> `manager.progress` ->
  // `DownloadsController`'s subscription) and that two-hop handoff needs
  // `runAsync`'s real zone to actually flush both hops.
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

  testWidgets('running download renders its progress bar', (tester) async {
    await pump(tester); // DownloadsController subscribes to manager.progress.
    expect(find.text('No active downloads.'), findsOneWidget);

    await settleAfter(
      tester,
      () => manager.enqueue(request, freeBytes: 1 << 30),
    );
    await emitAndSettle(
      tester,
      BackendProgressUpdate(
        request.taskId,
        progress: 0.4,
        expectedFileSizeBytes: 1000,
      ),
    );

    expect(find.text(friendlyName), findsOneWidget);
    expect(find.textContaining('Downloading'), findsOneWidget);
    // WS4: real percent + speed/ETA are surfaced (40% of 1000 bytes).
    expect(find.textContaining('40%'), findsOneWidget);
    final progressBar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progressBar.value, closeTo(0.4, 0.01));
  });

  testWidgets(
    'WS4: a completed download surfaces a "Ready — start chatting" card with '
    'a direct Start-chatting CTA',
    (tester) async {
      await pump(tester);
      await settleAfter(
        tester,
        () => manager.enqueue(request, freeBytes: 1 << 30),
      );
      // Drive to completion: file on disk + a complete status update.
      final file = File('${modelsDir.path}/${request.fileName}')
        ..writeAsBytesSync(List<int>.filled(request.expectedSizeBytes, 7));
      backend.filePaths[request.taskId] = file.path;
      await emitAndSettle(
        tester,
        BackendStatusUpdate(request.taskId, status: BackendTaskStatus.complete),
      );

      expect(find.text('Ready — start chatting'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Start chatting'),
        findsOneWidget,
      );
      // It leaves the "active downloads" list (it's done, not in flight).
      expect(find.byTooltip('Pause'), findsNothing);
    },
  );

  testWidgets(
    'WS4: a completed mmproj projector does NOT render a "Ready" card — it '
    'is not a chat-loadable model (registerAsInstalledModel: false)',
    (tester) async {
      final projector = DownloadRequest(
        repoId: 'ggml-org/SmolVLM2-2.2B-Instruct-GGUF',
        fileName: 'mmproj-SmolVLM2-2.2B-Instruct-f16.gguf',
        url: Uri.parse('https://huggingface.co/x/resolve/main/mmproj.gguf'),
        expectedSizeBytes: 1000,
        registerAsInstalledModel: false,
      );
      await pump(tester);
      await settleAfter(
        tester,
        () => manager.enqueue(projector, freeBytes: 1 << 30),
      );
      final file = File('${modelsDir.path}/${projector.fileName}')
        ..writeAsBytesSync(List<int>.filled(projector.expectedSizeBytes, 7));
      backend.filePaths[projector.taskId] = file.path;
      await emitAndSettle(
        tester,
        BackendStatusUpdate(
          projector.taskId,
          status: BackendTaskStatus.complete,
        ),
      );

      // No bogus green card, no model-less "Start chatting" CTA, and the raw
      // mmproj filename never surfaces.
      expect(find.text('Ready — start chatting'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Start chatting'), findsNothing);
      expect(find.textContaining('mmproj'), findsNothing);
    },
  );

  testWidgets('cancel calls the backend and removes the row', (tester) async {
    await pump(tester);
    await settleAfter(
      tester,
      () => manager.enqueue(request, freeBytes: 1 << 30),
    );
    await emitAndSettle(
      tester,
      BackendProgressUpdate(
        request.taskId,
        progress: 0.4,
        expectedFileSizeBytes: 1000,
      ),
    );
    expect(find.text(friendlyName), findsOneWidget);

    await settleAfter(tester, () => tester.tap(find.byTooltip('Cancel')));

    expect(backend.cancelCalls, contains(request.taskId));
    expect(find.text(friendlyName), findsNothing);
    expect(find.text('No active downloads.'), findsOneWidget);
  });

  testWidgets('a failed download shows the error and offers Retry + Dismiss '
      '(fixes the QA-filed retry-affordance gap)', (tester) async {
    await pump(tester);
    await settleAfter(
      tester,
      () => manager.enqueue(request, freeBytes: 1 << 30),
    );
    await emitAndSettle(
      tester,
      BackendStatusUpdate(
        request.taskId,
        status: BackendTaskStatus.failed,
        errorMessage: 'connection lost',
      ),
    );

    expect(find.text(friendlyName), findsOneWidget);
    expect(find.textContaining('Failed'), findsOneWidget);
    expect(find.text('connection lost'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.byTooltip('Dismiss'), findsOneWidget);
    // Failed rows use Dismiss, not the active-download Cancel tooltip.
    expect(find.byTooltip('Cancel'), findsNothing);

    // Tap Retry -> re-enqueues through DownloadsController.retry() ->
    // DownloadManager.enqueue() -> a fresh `queued` progress event, which
    // is only possible if a real enqueue happened (this row's earlier
    // "failed" state is gone, replaced by the queued one).
    await settleAfter(tester, () => tester.tap(find.text('Retry')));

    expect(backend.enqueuedRequests, contains(request.taskId));
    expect(find.text(friendlyName), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(find.textContaining('Failed'), findsNothing);
    expect(find.textContaining('Queued'), findsOneWidget);
  });

  testWidgets(
    'retry re-enqueues without the original quant/license (a size-only '
    'DownloadRequest reconstructed from repoId + fileName) but still '
    'passes it through the real free-space guard',
    (tester) async {
      await pump(tester);
      await settleAfter(
        tester,
        () => manager.enqueue(request, freeBytes: 1 << 30),
      );
      await emitAndSettle(
        tester,
        BackendStatusUpdate(
          request.taskId,
          status: BackendTaskStatus.failed,
          errorMessage: 'connection lost',
        ),
      );

      await settleAfter(tester, () => tester.tap(find.text('Retry')));

      // The retry request is rebuilt from repoId + fileName (see
      // DownloadsController.retry's doc comment) via the same
      // HfApiClient.resolveDownloadUrl the model detail screen uses — not
      // the arbitrary `request.url` this test fixture made up.
      final reEnqueued = backend.enqueuedRequests[request.taskId]!;
      expect(reEnqueued.fileName, request.fileName);
      expect(
        reEnqueued.url.toString(),
        'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/'
        'resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      );
    },
  );
}
