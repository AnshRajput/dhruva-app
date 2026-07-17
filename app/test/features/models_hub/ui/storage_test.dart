// Installed tab: delete removes both the drift row and the file, with a
// confirmation dialog in between (T5 test requirement).

import 'dart:io';

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/hf_api/hf_api_client.dart';
import 'package:dhruva/features/models_hub/ui/models_hub_screen.dart';
import 'package:drift/drift.dart' show Value;
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
  late Directory tempDir;
  late File modelFile;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync(
      'dhruva_storage_widget_test_',
    );
    modelFile = File('${tempDir.path}/a.gguf')..writeAsBytesSync([1, 2, 3]);
    await db
        .into(db.installedModels)
        .insert(
          InstalledModelsCompanion.insert(
            repoId: 'bartowski/Llama-3.2-1B-Instruct-GGUF',
            fileName: 'Llama-3.2-1B-Instruct-Q4_K_M.gguf',
            quant: const Value('Q4_K_M'),
            sizeBytes: 3,
            localPath: modelFile.path,
            downloadedAt: DateTime.utc(2026, 7, 17),
          ),
        );
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('delete removes the installed model after confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
          hfApiClientProvider.overrideWithValue(
            HfApiClient(
              client: MockClient((request) async => http.Response('[]', 200)),
            ),
          ),
        ],
        child: const MaterialApp(home: ModelsHubScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Installed'));
    await tester.pumpAndSettle();

    expect(find.text('bartowski/Llama-3.2-1B-Instruct-GGUF'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Delete model?'), findsOneWidget);
    // `StorageManager.delete` awaits a real `dart:io` `File.delete()` — that
    // real async gap needs `runAsync` to resolve inside `testWidgets`'s fake
    // clock (see Flutter's own `TestWidgetsFlutterBinding.runAsync` docs).
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.text('bartowski/Llama-3.2-1B-Instruct-GGUF'), findsNothing);
    expect(await db.select(db.installedModels).get(), isEmpty);
    expect(modelFile.existsSync(), isFalse);
  });
}
