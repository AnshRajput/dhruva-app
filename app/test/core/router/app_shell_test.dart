// Global download indicator (Amendment 4b): the Models bottom-nav
// destination shows a live badge while any download is active
// (queued/running/paused/verifying) and hides it once the download
// completes — proven end-to-end through the real DownloadManager wired to
// a FakeDownloadBackend, same harness shape as downloads_screen_test.dart.

import 'dart:async';
import 'dart:io';

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/downloads/download_backend.dart';
import 'package:dhruva/data/downloads/download_manager.dart';
import 'package:dhruva/data/downloads/fake_download_backend.dart';
import 'package:dhruva/data/hf_api/hf_api_client.dart';
import 'package:dhruva/main.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
    modelsDir = Directory.systemTemp.createTempSync(
      'dhruva_shell_widget_test_',
    );
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
            HfApiClient(
              client: MockClient((request) async => http.Response('[]', 200)),
            ),
          ),
        ],
        child: const DhruvaApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Same two-hop-StreamController flush shape as downloads_screen_test.dart.
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

  bool anyBadgeVisible(WidgetTester tester) =>
      tester.widgetList<Badge>(find.byType(Badge)).any((b) => b.isLabelVisible);

  testWidgets('no badge before any download starts', (tester) async {
    await pumpApp(tester);

    expect(anyBadgeVisible(tester), isFalse);
  });

  testWidgets('badge appears once a download is running, disappears once it '
      'completes', (tester) async {
    await pumpApp(tester);
    expect(anyBadgeVisible(tester), isFalse);

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
    expect(anyBadgeVisible(tester), isTrue);

    final file = File('${modelsDir.path}/${request.fileName}')
      ..writeAsBytesSync([1, 2, 3, 4, 5]);
    backend.filePaths[request.taskId] = file.path;
    await emitAndSettle(
      tester,
      BackendStatusUpdate(request.taskId, status: BackendTaskStatus.complete),
    );

    expect(anyBadgeVisible(tester), isFalse);
  });
}
