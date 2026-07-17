import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/engine_bindings/fake_engine_service.dart';
import 'package:dhruva/features/chat/state/chat_controller.dart';
import 'package:dhruva/features/chat/ui/sampling_settings_sheet.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _fakeDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  const args = ChatRouteArgs();

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
        engineServiceProvider.overrideWithValue(FakeEngineService()),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> pumpSheet(WidgetTester tester) async {
    await container.read(chatControllerProvider(args).future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showSamplingSettingsSheet(context, args),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows default SamplingParams values', (tester) async {
    await pumpSheet(tester);

    expect(find.text('Temperature'), findsOneWidget);
    expect(find.text('0.80'), findsOneWidget);
    expect(find.text('40'), findsOneWidget); // Top-K default
    expect(find.text('512'), findsOneWidget); // Max tokens default
  });

  testWidgets('reset restores defaults after a drag', (tester) async {
    await pumpSheet(tester);

    final slider = find.byType(Slider).first; // temperature
    await tester.drag(slider, const Offset(-200, 0)); // drag toward 0
    await tester.pump();
    expect(find.text('0.80'), findsNothing);

    await tester.ensureVisible(find.text('Reset to defaults'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset to defaults'));
    await tester.pump();
    expect(find.text('0.80'), findsOneWidget);
  });

  testWidgets(
    'Done persists the system prompt and sampling params, closes the sheet',
    (tester) async {
      await pumpSheet(tester);

      await tester.enterText(find.byType(TextField).first, 'Be concise.');
      await tester.ensureVisible(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.text('open'), findsOneWidget); // sheet closed
      final state = container.read(chatControllerProvider(args)).value!;
      expect(state.systemPrompt, 'Be concise.');
      expect(state.samplingParams.temperature, 0.8);
    },
  );
}
