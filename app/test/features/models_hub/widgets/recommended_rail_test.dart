// Recommended rail (Amendment 4c + Amendment 7 fix): the rail must never
// contradict itself. Under "Recommended for your device" it shows ONLY models
// that actually fit (comfortable/possible), best-first. If NONE fit, it falls
// back to "Smallest models to try" with a gentle "May be slow" note — never a
// red "Not recommended" chip inside a "Recommended" section.

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/features/models_hub/state/recommended_models_provider.dart';
import 'package:dhruva/features/models_hub/widgets/recommended_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Future<void> _pump(WidgetTester tester, int totalRamBytes) async {
  // Widen the surface so the horizontal ListView mounts all its cards
  // (findsN* isn't scroll-dependent).
  await tester.binding.setSurfaceSize(const Size(1400, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deviceInfoServiceProvider.overrideWithValue(
          FakeDeviceInfoService(
            memory: DeviceMemoryInfo(
              totalBytes: totalRamBytes,
              availableBytes: totalRamBytes,
            ),
            storage: const DeviceStorageInfo(
              totalBytes: 64000000000,
              freeBytes: 32000000000,
            ),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(body: RecommendedRail()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('high-RAM device: header is "Recommended for your device" and '
      'every shown model is Comfortable — no contradictory chip', (
    tester,
  ) async {
    await _pump(tester, 10 * 1024 * 1024 * 1024);

    expect(find.text('Recommended for your device'), findsOneWidget);
    expect(find.text('Smallest models to try'), findsNothing);
    expect(find.text('Comfortable'), findsNWidgets(starterModelCatalog.length));
    // THE bug this fixes: never show "Not recommended" under "Recommended".
    expect(find.text('Not recommended'), findsNothing);
  });

  testWidgets('mid-RAM device: only the fitting models are shown, and NONE '
      'are labelled "Not recommended"', (tester) async {
    await _pump(tester, 5 * 1024 * 1024 * 1024);

    expect(find.text('Recommended for your device'), findsOneWidget);
    expect(find.text('Possible'), findsWidgets);
    // The too-big models are filtered OUT of the rail, not shown as
    // "Not recommended" inside it.
    expect(find.text('Not recommended'), findsNothing);
  });

  testWidgets('low-RAM device (nothing fits): falls back to "Smallest models '
      'to try" with a gentle "May be slow" note — never "Not recommended"', (
    tester,
  ) async {
    await _pump(tester, 3 * 1024 * 1024 * 1024);

    // No contradictory section/label anywhere.
    expect(find.text('Recommended for your device'), findsNothing);
    expect(find.text('Not recommended'), findsNothing);
    // Honest fallback instead.
    expect(find.text('Smallest models to try'), findsOneWidget);
    expect(find.text('May be slow'), findsWidgets);
  });

  testWidgets('the low-RAM fallback includes the smallest model', (
    tester,
  ) async {
    await _pump(tester, 3 * 1024 * 1024 * 1024);
    final smallest =
        starterModelCatalog.toList()
          ..sort((a, b) => a.approxSizeBytes.compareTo(b.approxSizeBytes));
    expect(find.text(smallest.first.displayName), findsOneWidget);
  });

  testWidgets(
    'tapping a recommended card navigates to its model detail route',
    (tester) async {
      final pushed = <String>[];
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) =>
                const Scaffold(body: RecommendedRail()),
          ),
          GoRoute(
            path: '/models/repo/:id',
            builder: (context, state) {
              pushed.add(state.pathParameters['id']!);
              return const Text('detail');
            },
          ),
        ],
      );
      await tester.binding.setSurfaceSize(const Size(1400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deviceInfoServiceProvider.overrideWithValue(
              const FakeDeviceInfoService(
                memory: DeviceMemoryInfo(
                  totalBytes: 10 * 1024 * 1024 * 1024,
                  availableBytes: 10 * 1024 * 1024 * 1024,
                ),
                storage: DeviceStorageInfo(
                  totalBytes: 64000000000,
                  freeBytes: 32000000000,
                ),
              ),
            ),
          ],
          child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      final firstShown = starterModelCatalog.first;
      await tester.tap(find.text(firstShown.displayName));
      await tester.pumpAndSettle();

      expect(find.text('detail'), findsOneWidget);
      expect(pushed, [firstShown.repoId]);
    },
  );
}
