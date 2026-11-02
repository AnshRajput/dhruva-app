// Wave 5 polish on the Models hub: advanced Hugging Face search is one tap from
// the app bar (parity row 37), the Voice tab speaks plain words with the
// technical parts under Advanced, and iOS gets a segmented control instead of
// Material underline tabs (Rule 6).

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/features/models_hub/state/voice_models_controller.dart';
import 'package:dhruva/features/models_hub/ui/models_hub_screen.dart';
import 'package:dhruva/voice/voice_model_catalog.dart';
import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart' show CupertinoSlidingSegmentedControl;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../../support/mock_hf_client.dart';

const _fakeDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

/// Every voice model not installed, with no disk or downloads involved.
class _FakeVoiceModels extends VoiceModelsController {
  @override
  Future<List<VoiceModelState>> build() async => [
    for (final e in voiceModelCatalog)
      VoiceModelState(entry: e, status: VoiceModelStatus.notInstalled),
  ];
}

Future<void> _pump(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.android,
  List<String>? pushed,
}) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await tester.binding.setSurfaceSize(const Size(500, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const ModelsHubScreen()),
      GoRoute(
        path: '/models/search',
        builder: (context, state) {
          pushed?.add(state.uri.path);
          return const Text('advanced-search');
        },
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
        voiceModelsControllerProvider.overrideWith(_FakeVoiceModels.new),
        hfApiClientProvider.overrideWithValue(
          mockHfClient(MockClient((r) async => http.Response('[]', 200))),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark.copyWith(platform: platform),
        // Reduced motion: the DhruvaLoader rests instead of looping, so the
        // tests can settle while the Voice tab loads.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'advanced HF search is an app-bar action, not just the list foot',
    (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const ValueKey('models-hf-search')));
      await tester.pumpAndSettle();
      expect(find.text('advanced-search'), findsOneWidget);
    },
  );

  testWidgets('Voice tab: plain copy up front, model details under Advanced', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('Voice'));
    await tester.pumpAndSettle();

    expect(find.text('Talk hands-free'), findsOneWidget);
    expect(find.text('Install voice bundle'), findsOneWidget);
    // Jargon never on the primary surface.
    for (final jargon in [
      'int8',
      'VITS',
      'VAD',
      'Silero',
      'Piper',
      'Whisper',
    ]) {
      expect(find.textContaining(jargon), findsNothing, reason: jargon);
    }
    // ...and it is all there once Advanced opens.
    await tester.tap(find.byKey(const ValueKey('voice-advanced')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Silero VAD'), findsWidgets);
  });

  testWidgets('iOS: a segmented control, no Material TabBar', (tester) async {
    await _pump(tester, platform: TargetPlatform.iOS);
    expect(find.byType(TabBar), findsNothing);
    expect(find.byKey(const ValueKey('models-tabs')), findsOneWidget);
    expect(find.byType(CupertinoSlidingSegmentedControl<int>), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('models-tabs')),
        matching: find.text('Installed'),
      ),
    );
    await tester.pumpAndSettle();
    // The Installed body is showing (its empty state).
    expect(find.textContaining('No models installed yet'), findsOneWidget);
  });

  testWidgets('Android keeps the Material TabBar', (tester) async {
    await _pump(tester);
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.byKey(const ValueKey('models-tabs')), findsNothing);
  });
}
