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
}
