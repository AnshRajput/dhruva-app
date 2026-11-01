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
    // A phone-sized surface: the plain-language sheet is taller than the
    // default 800x600 test view.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await container.read(chatControllerProvider(args).future);
    // chatControllerProvider is autoDispose (B1) — in the real app it's
    // kept alive by the ChatThreadScreen's own `ref.watch`, which stays
    // mounted (just covered by the modal) for as long as this sheet is
    // open. This test's Scaffold never watches the provider itself, so a
    // manual `container.listen` stands in for that always-present screen
    // subscription rather than the provider getting disposed the instant
    // this bare `.read` above returns.
    final sub = container.listen(chatControllerProvider(args), (_, _) {});
    addTearDown(sub.close);
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

  testWidgets('uses plain language and keeps Top-P / Top-K under Advanced', (
    tester,
  ) async {
    await pumpSheet(tester);

    expect(find.text('Chat settings'), findsOneWidget);
    expect(find.text('Instructions for this chat'), findsOneWidget);
    expect(find.text('Creativity'), findsOneWidget);
    expect(find.text('Answer length'), findsOneWidget);
    expect(find.text('Memory for this chat'), findsOneWidget);
    // Jargon labels are gone from the main surface.
    expect(find.text('Temperature'), findsNothing);
    expect(find.text('Max tokens'), findsNothing);
    expect(find.text('Context length'), findsNothing);
    expect(find.text('System prompt & sampling'), findsNothing);
    // Top-P / Top-K only appear once Advanced is opened.
    expect(find.text('Top-P'), findsNothing);
    expect(find.text('Top-K'), findsNothing);
    await tester.ensureVisible(find.text('Advanced'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    expect(find.text('Top-P'), findsOneWidget);
    expect(find.text('Top-K'), findsOneWidget);
  });

  testWidgets('shows default SamplingParams values', (tester) async {
    await pumpSheet(tester);

    expect(find.text('0.80'), findsOneWidget); // Creativity default
    expect(find.text('512'), findsOneWidget); // Answer length default
    expect(find.text('4096'), findsOneWidget); // Memory default
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
