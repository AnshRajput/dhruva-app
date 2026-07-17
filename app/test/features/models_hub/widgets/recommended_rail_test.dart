// Recommended rail (Amendment 4c): the starter catalog renders with a tier
// verdict computed against whatever device RAM `deviceInfoServiceProvider`
// reports — exercised across all three `ModelTier` values.

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
  // ListView.separated only builds children inside/near its viewport — the
  // default 800px test surface leaves the last card or two off-screen and
  // unbuilt. Widen it so all five starter-catalog cards actually mount and
  // findsNWidgets on their verdict chips isn't scroll-dependent.
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
  testWidgets('renders every catalog entry with its display name', (
    tester,
  ) async {
    await _pump(tester, 8 * 1024 * 1024 * 1024);

    expect(find.text('Recommended for your device'), findsOneWidget);
    for (final model in starterModelCatalog) {
      expect(find.text(model.displayName), findsOneWidget);
    }
  });

  testWidgets('low-RAM device: every model verdicts Not recommended', (
    tester,
  ) async {
    await _pump(tester, 3 * 1024 * 1024 * 1024);

    expect(
      find.text('Not recommended'),
      findsNWidgets(starterModelCatalog.length),
    );
    expect(find.text('Comfortable'), findsNothing);
    expect(find.text('Possible'), findsNothing);
  });

  testWidgets('mid-RAM device: 1B-class comfortable-floor models read '
      'Possible, larger ones still Not recommended', (tester) async {
    await _pump(tester, 5 * 1024 * 1024 * 1024);

    expect(find.text('Possible'), findsWidgets);
    expect(find.text('Not recommended'), findsWidgets);
  });

  testWidgets('high-RAM device: every model verdicts Comfortable', (
    tester,
  ) async {
    await _pump(tester, 10 * 1024 * 1024 * 1024);

    expect(find.text('Comfortable'), findsNWidgets(starterModelCatalog.length));
    expect(find.text('Possible'), findsNothing);
    expect(find.text('Not recommended'), findsNothing);
  });

  testWidgets(
    // QA (Loop-4 attack list #6): the exact 4GB floor named in
    // orchestra/CLAUDE.md ("1B -> 4GB+ RAM, 3-4B -> 6GB+") — right at the
    // 1B-class floor and below the 3-4B-class floor, so the catalog splits
    // cleanly into a real mix instead of an all-one-verdict device.
    'exactly-4GB device (the documented 1B-class RAM floor): 1B/1.5B/1.7B '
    'class models read Possible, 3B+ class models read Not recommended',
    (tester) async {
      await _pump(tester, 4 * 1024 * 1024 * 1024);

      expect(find.text('Possible'), findsNWidgets(3)); // 1B, 1.5B, 1.7B
      expect(find.text('Not recommended'), findsNWidgets(2)); // 3B, Phi-4 mini
      expect(find.text('Comfortable'), findsNothing);
    },
  );

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
                  totalBytes: 8 * 1024 * 1024 * 1024,
                  availableBytes: 8 * 1024 * 1024 * 1024,
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

      final firstModel = starterModelCatalog.first;
      await tester.tap(find.text(firstModel.displayName));
      await tester.pumpAndSettle();

      expect(find.text('detail'), findsOneWidget);
      // go_router decodes path parameters for us — the URL segment itself was
      // percent-encoded (Uri.encodeComponent in recommended_rail.dart, per
      // app_router.dart's "repo ids contain a slash" note), but
      // `state.pathParameters['id']` hands back the decoded repoId.
      expect(pushed, [firstModel.repoId]);
    },
  );
}
