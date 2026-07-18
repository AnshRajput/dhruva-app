// WS1: the curated catalog is the default Models experience. Each card states
// a friendly name + "best for" + size + device verdict + ONE download button;
// the whole card opens the detail screen; a secondary button reaches the
// advanced HF search.

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/features/models_hub/state/listing_download_controller.dart';
import 'package:dhruva/features/models_hub/state/recommended_models_provider.dart';
import 'package:dhruva/features/models_hub/widgets/curated_model_card.dart';
import 'package:dhruva/features/models_hub/widgets/curated_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _StubController extends ListingDownloadController {
  @override
  Future<Map<String, ListingModelState>> build() async => {};
}

/// Seeds a single repo in the `failed` state so the card's error-surface path
/// is exercised.
class _FailedController extends ListingDownloadController {
  _FailedController(this.repoId, this.message);
  final String repoId;
  final String message;
  @override
  Future<Map<String, ListingModelState>> build() async => {
    repoId: ListingModelState(
      status: ListingModelStatus.failed,
      errorMessage: message,
    ),
  };
}

const _fakeDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

Future<GoRouter> _pumpTab(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(500, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final pushed = <String>[];
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: CuratedTab()),
      ),
      GoRoute(
        path: '/models/repo/:id',
        builder: (context, state) {
          pushed.add(state.pathParameters['id']!);
          return const Text('detail');
        },
      ),
      GoRoute(
        path: '/models/search',
        builder: (context, state) => const Text('advanced-search'),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
        listingDownloadControllerProvider.overrideWith(_StubController.new),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  // Stash the push log on the router for the caller (via a closure capture).
  _pushedByRouter[router] = pushed;
  return router;
}

final _pushedByRouter = <GoRouter, List<String>>{};

void main() {
  testWidgets('renders a curated card with name, best-for, size and verdict', (
    tester,
  ) async {
    await _pumpTab(tester);

    // Best-fit-first on an 8GB device leads with the smallest comfortable pick.
    final first = starterModelCatalog
        .where((m) => !m.isVision)
        .reduce((a, b) => a.approxSizeBytes <= b.approxSizeBytes ? a : b);
    expect(find.text(first.displayName), findsOneWidget);
    expect(find.text(first.bestFor), findsOneWidget);
    // A verdict chip is shown (device RAM is known).
    expect(find.text('Comfortable'), findsWidgets);
    // Exactly one download button per card that isn't installed/downloading.
    expect(find.byTooltip('Download'), findsWidgets);
  });

  testWidgets('tapping a card opens its detail route', (tester) async {
    final router = await _pumpTab(tester);
    final first = starterModelCatalog
        .where((m) => !m.isVision)
        .reduce((a, b) => a.approxSizeBytes <= b.approxSizeBytes ? a : b);

    await tester.tap(find.text(first.displayName));
    await tester.pumpAndSettle();

    expect(find.text('detail'), findsOneWidget);
    expect(_pushedByRouter[router], contains(first.repoId));
  });

  testWidgets('advanced-search button navigates to the demoted HF search', (
    tester,
  ) async {
    await _pumpTab(tester);
    await tester.tap(find.text('Search all of Hugging Face (advanced)'));
    await tester.pumpAndSettle();
    expect(find.text('advanced-search'), findsOneWidget);
  });

  testWidgets('a failed one-tap download shows its reason on the card', (
    tester,
  ) async {
    final model = starterModelCatalog.first;
    const reason =
        'Gated on Hugging Face — requires sign-in, not supported '
        'yet.';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          listingDownloadControllerProvider.overrideWith(
            () => _FailedController(model.repoId, reason),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: CuratedModelCard(model: model, totalRamBytes: 8000000000),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(reason), findsOneWidget);
  });

  testWidgets('a vision entry carries a Vision badge', (tester) async {
    final vision = starterModelCatalog.firstWhere((m) => m.isVision);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          listingDownloadControllerProvider.overrideWith(_StubController.new),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: CuratedModelCard(model: vision, totalRamBytes: 8000000000),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Vision'), findsOneWidget);
    expect(find.byTooltip('Download'), findsOneWidget);
  });

  testWidgets(
    'segments non-fitting models into a collapsed "Larger models" group and '
    'badges the recommended pick (critic HIGH)',
    (tester) async {
      // A low-RAM device: the biggest curated models do not fit, so they must
      // NOT sit under the "Runs great" header — they go under "Larger models".
      // 5 GB: small (≤1.2GB file, 4GB floor) models are "possible" and fit,
      // but the 1.2–3GB-file models (6GB floor) are "not recommended" — a real
      // split, so the collapsed group and the badge both render.
      const lowRam = FakeDeviceInfoService(
        memory: DeviceMemoryInfo(
          totalBytes: 5000000000,
          availableBytes: 2500000000,
        ),
        storage: DeviceStorageInfo(
          totalBytes: 64000000000,
          freeBytes: 32000000000,
        ),
      );
      await tester.binding.setSurfaceSize(const Size(500, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deviceInfoServiceProvider.overrideWithValue(lowRam),
            listingDownloadControllerProvider.overrideWith(_StubController.new),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(body: CuratedTab()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The best fitting pick is badged, and the too-big models are hidden in
      // the collapsed group (so the screen never promises "runs great" for a
      // model this phone can't run).
      expect(find.text('Recommended'), findsOneWidget);
      expect(find.text('Larger models'), findsOneWidget);
    },
  );
}
