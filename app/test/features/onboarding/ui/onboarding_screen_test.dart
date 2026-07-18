// WS2: the guided first-run flow. Welcome states the value; "pick" shows the
// curated catalog ONLY (no raw HF firehose, no quant menu) with the
// device-appropriate model badged "Recommended" and pre-selected; skipping
// marks onboarding done (shown once) and lands in chat.

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/features/onboarding/state/onboarding_controller.dart';
import 'package:dhruva/features/onboarding/ui/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeOnboardingStore implements OnboardingStore {
  bool complete = false;
  @override
  Future<bool> isComplete() async => complete;
  @override
  Future<void> markComplete() async => complete = true;
}

/// Keeps the flow off the real download pipeline (platform channels) for the
/// welcome/pick/skip paths — the download itself is covered in the state test.
class _StubDownloadController extends OnboardingDownloadController {
  @override
  Future<OnboardingDownloadState> build() async =>
      const OnboardingDownloadState();
}

const _fakeDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

Future<_FakeOnboardingStore> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(420, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final store = _FakeOnboardingStore();
  final router = GoRouter(
    initialLocation: '/onboarding',
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/chat',
        builder: (context, state) => const Text('chat-home'),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
        onboardingStoreProvider.overrideWith((ref) async => store),
        onboardingDownloadControllerProvider.overrideWith(
          _StubDownloadController.new,
        ),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

void main() {
  testWidgets('welcome states what Dhruva is and the value', (tester) async {
    await _pump(tester);
    expect(find.text('Welcome to Dhruva'), findsOneWidget);
    expect(
      find.text('A private AI that runs entirely on your phone.'),
      findsOneWidget,
    );
    expect(find.text('Get started'), findsOneWidget);
  });

  testWidgets('skip on welcome marks onboarding done and lands in chat', (
    tester,
  ) async {
    final store = await _pump(tester);
    expect(store.complete, isFalse);

    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();

    expect(store.complete, isTrue); // shown once
    expect(find.text('chat-home'), findsOneWidget);
  });

  testWidgets(
    'pick step shows the curated catalog with a single Recommended badge, '
    'no firehose and no quant menu',
    (tester) async {
      await _pump(tester);
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();

      expect(find.text('Pick your first model'), findsOneWidget);
      // Exactly one device-appropriate default is badged.
      expect(find.text('Recommended'), findsOneWidget);
      // No raw HF firehose entry, no quant jargon anywhere in the flow.
      expect(find.textContaining('Hugging Face'), findsNothing);
      expect(find.textContaining('Q4'), findsNothing);
      expect(find.textContaining('quant'), findsNothing);
      // The one obvious next step downloads the selected model in one tap.
      expect(find.textContaining('Download'), findsWidgets);
    },
  );

  testWidgets('skip on the pick step also marks onboarding done', (
    tester,
  ) async {
    final store = await _pump(tester);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();

    expect(store.complete, isTrue);
    expect(find.text('chat-home'), findsOneWidget);
  });
}
