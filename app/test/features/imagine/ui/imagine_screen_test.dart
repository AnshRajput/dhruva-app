import 'dart:io';

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/engine_bindings/fake_engine_service.dart';
import 'package:dhruva/features/imagine/ui/imagine_screen.dart';
import 'package:dhruva/imagine_engine/fake_image_gen_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _highRam = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

const _lowRam = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 3000000000, availableBytes: 1000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

void main() {
  late AppDatabase db;
  late Directory sdDir;
  late Directory generatedDir;
  late FakeImageGenService fakeImageGen;
  late FakeEngineService fakeEngine;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    sdDir = await Directory.systemTemp.createTemp('imagine_screen_sd');
    generatedDir = await Directory.systemTemp.createTemp('imagine_screen_gen');
    fakeImageGen = FakeImageGenService(
      stepDelay: const Duration(milliseconds: 5),
    );
    fakeEngine = FakeEngineService();
  });

  tearDown(() async {
    await db.close();
    await sdDir.delete(recursive: true);
    await generatedDir.delete(recursive: true);
  });

  Widget buildApp({FakeDeviceInfoService deviceInfo = _highRam}) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        deviceInfoServiceProvider.overrideWithValue(deviceInfo),
        imageGenServiceProvider.overrideWithValue(fakeImageGen),
        engineServiceProvider.overrideWithValue(fakeEngine),
        sdModelsDirectoryProvider.overrideWith((ref) async => sdDir),
        generatedImagesDirectoryProvider.overrideWith(
          (ref) async => generatedDir,
        ),
      ],
      child: MaterialApp(theme: AppTheme.dark, home: const ImagineScreen()),
    );
  }

  testWidgets('below the RAM floor shows the gated state, not the studio', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp(deviceInfo: _lowRam));
    await tester.pumpAndSettle();

    expect(find.text('Needs a higher-memory device'), findsOneWidget);
    expect(find.text('Create'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('above the RAM floor with no checkpoint shows the import CTA', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Create'), findsOneWidget);
    expect(find.text('No image model installed'), findsOneWidget);
    expect(find.text('Import a model file'), findsOneWidget);
  });

  testWidgets(
    'with a checkpoint installed, the studio renders prompt + controls',
    (tester) async {
      File('${sdDir.path}/model.safetensors').writeAsBytesSync([1]);

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('No image model installed'), findsNothing);
      expect(find.widgetWithText(TextField, 'Prompt'), findsOneWidget);
      expect(find.text('Generate'), findsOneWidget);
      expect(find.text('Steps'), findsOneWidget);
      expect(find.text('CFG scale'), findsOneWidget);
      expect(find.text('384×384'), findsOneWidget);
    },
  );

  testWidgets(
    'generate streams progress then shows the result image, and it lands '
    'in the gallery',
    (tester) async {
      File('${sdDir.path}/model.safetensors').writeAsBytesSync([1]);
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Prompt'),
        'a lone pole star',
      );
      await tester.tap(find.text('Generate'));
      await tester.pump(); // start the loadModel/generate future
      await tester.pump(const Duration(milliseconds: 6));

      expect(find.textContaining('Step '), findsOneWidget);

      await tester.pumpAndSettle();

      expect(find.text('Save / Share'), findsOneWidget);
      expect(find.text('Generate another'), findsOneWidget);
      expect(find.byType(Image), findsWidgets);

      // Switch to the Gallery tab — the freshly generated image is there.
      await tester.tap(find.text('Gallery'));
      await tester.pumpAndSettle();
      expect(find.text('No images yet'), findsNothing);
    },
  );

  testWidgets('cancel mid-generation shows the cancelled state', (
    tester,
  ) async {
    fakeImageGen = FakeImageGenService(
      stepDelay: const Duration(milliseconds: 40),
    );
    File('${sdDir.path}/model.safetensors').writeAsBytesSync([1]);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Prompt'), 'a cat');
    await tester.tap(find.text('Generate'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // The cancel button lives inside the progress ring.
    await tester.tap(find.byTooltip('Cancel generation'));
    await tester.pumpAndSettle();

    expect(find.text('Cancelled'), findsOneWidget);
  });
}
