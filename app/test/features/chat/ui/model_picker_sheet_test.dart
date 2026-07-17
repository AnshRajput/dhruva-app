import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/downloads/storage_manager.dart';
import 'package:dhruva/features/chat/ui/model_picker_sheet.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _fakeDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertModel({required String repoId, int sizeBytes = 100}) {
    return db
        .into(db.installedModels)
        .insert(
          InstalledModelsCompanion.insert(
            repoId: repoId,
            fileName: 'model.gguf',
            sizeBytes: sizeBytes,
            localPath: '/tmp/dhruva-picker-test.gguf',
            downloadedAt: DateTime.utc(2026, 7, 17),
          ),
        );
  }

  Widget buildApp() {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                await showModelPickerSheet(context);
              },
              child: const Text('open picker'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('lists installed models and returns the tapped one', (
    tester,
  ) async {
    await insertModel(repoId: 'bartowski/Llama-3.2-1B-Instruct-GGUF');
    await insertModel(repoId: 'bartowski/Qwen2.5-1.5B-Instruct-GGUF');
    InstalledModelInfo? picked;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  picked = await showModelPickerSheet(context);
                },
                child: const Text('open picker'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open picker'));
    await tester.pumpAndSettle();

    expect(find.text('Llama-3.2-1B-Instruct'), findsOneWidget);
    expect(find.text('Qwen2.5-1.5B-Instruct'), findsOneWidget);

    await tester.tap(find.text('Llama-3.2-1B-Instruct'));
    await tester.pumpAndSettle();

    expect(picked?.repoId, 'bartowski/Llama-3.2-1B-Instruct-GGUF');
  });

  testWidgets('no installed models shows an empty message', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.tap(find.text('open picker'));
    await tester.pumpAndSettle();

    expect(find.text('No models installed yet.'), findsOneWidget);
  });

  group('Loop 7: vision discoverability hint', () {
    const hintText = 'Want to chat about photos? Browse vision models →';

    testWidgets('no installed models: the vision hint is shown', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('open picker'));
      await tester.pumpAndSettle();

      expect(find.text(hintText), findsOneWidget);
    });

    testWidgets(
      'installed models exist but none are vision-capable: hint is shown',
      (tester) async {
        await insertModel(repoId: 'bartowski/Llama-3.2-1B-Instruct-GGUF');
        await tester.pumpWidget(buildApp());
        await tester.tap(find.text('open picker'));
        await tester.pumpAndSettle();

        expect(find.text(hintText), findsOneWidget);
      },
    );

    testWidgets('a vision-capable model is installed: hint is hidden', (
      tester,
    ) async {
      await db
          .into(db.installedModels)
          .insert(
            InstalledModelsCompanion.insert(
              repoId: 'ggml-org/SmolVLM-500M-Instruct-GGUF',
              fileName: 'vision.gguf',
              sizeBytes: 100,
              localPath: '/tmp/dhruva-picker-vision-test.gguf',
              downloadedAt: DateTime.utc(2026, 7, 17),
              mmprojPath: const Value('/tmp/dhruva-picker-mmproj.gguf'),
              isVision: const Value(true),
            ),
          );
      await tester.pumpWidget(buildApp());
      await tester.tap(find.text('open picker'));
      await tester.pumpAndSettle();

      expect(find.text(hintText), findsNothing);
    });

    testWidgets('tapping the hint closes the sheet and navigates to /models', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/chat',
        routes: [
          GoRoute(
            path: '/chat',
            builder: (context, state) => Scaffold(
              body: Builder(
                builder: (context) => FilledButton(
                  onPressed: () => showModelPickerSheet(context),
                  child: const Text('open picker'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/models',
            builder: (context, state) =>
                const Scaffold(body: Text('models hub stand-in')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
          ],
          child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
        ),
      );

      await tester.tap(find.text('open picker'));
      await tester.pumpAndSettle();
      expect(find.text(hintText), findsOneWidget);

      await tester.tap(find.text(hintText));
      await tester.pumpAndSettle();

      expect(find.text('models hub stand-in'), findsOneWidget);
    });
  });
}
