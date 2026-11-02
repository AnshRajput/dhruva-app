// Installed tab: delete removes both the drift row and the file, with a
// confirmation dialog in between (T5 test requirement).

import 'dart:io';

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/features/models_hub/ui/models_hub_screen.dart';
import 'package:drift/drift.dart' show Value;
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
            mockHfClient(
              MockClient((request) async => http.Response('[]', 200)),
            ),
          ),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const ModelsHubScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Installed'));
    await tester.pumpAndSettle();

    // WS1: a curated repo shows its FRIENDLY name here, not the raw repo id.
    expect(find.text('Llama 3.2 1B Instruct'), findsOneWidget);
    expect(find.text('bartowski/Llama-3.2-1B-Instruct-GGUF'), findsNothing);

    // Chat and Delete live in a labelled overflow, not as bare icons.
    await tester.tap(find.byTooltip('Model actions'));
    await tester.pumpAndSettle();
    expect(find.text('Chat'), findsOneWidget);
    await tester.tap(find.text('Delete'));
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

    expect(find.text('Llama 3.2 1B Instruct'), findsNothing);
    expect(await db.select(db.installedModels).get(), isEmpty);
    expect(modelFile.existsSync(), isFalse);
  });

  testWidgets('D11: on a narrow phone the "installed" line and the Import '
      'button stack instead of colliding; labels are plain', (tester) async {
    // 280 dp wide at a large text scale: the worst case for the old Row.
    await tester.binding.setSurfaceSize(const Size(280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
          hfApiClientProvider.overrideWithValue(
            mockHfClient(
              MockClient((request) async => http.Response('[]', 200)),
            ),
          ),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const ModelsHubScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Installed'));
    await tester.pumpAndSettle();

    // No overflow exception was thrown while laying this out.
    expect(tester.takeException(), isNull);
    final summary = find.textContaining('1 installed');
    final button = find.widgetWithText(OutlinedButton, 'Import a model file');
    expect(summary, findsOneWidget);
    expect(button, findsOneWidget);
    final a = tester.getRect(summary);
    final b = tester.getRect(button);
    expect(
      a.overlaps(b),
      isFalse,
      reason: 'summary and Import must not collide',
    );
    // Stacked: the button sits below the summary text, with a gutter.
    if (a.bottom <= b.top) {
      expect(b.top - a.bottom, greaterThanOrEqualTo(8));
    }

    // Jargon-free row: Balanced, not Q4_K_M / .gguf.
    expect(find.textContaining('Balanced'), findsOneWidget);
    expect(find.textContaining('Q4_K_M'), findsNothing);
    expect(find.textContaining('.gguf'), findsNothing);
  });
}
