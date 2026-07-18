// WS1: the DEFAULT Models experience is the curated catalog (Discover tab),
// not the raw Hugging Face search firehose. The firehose is demoted behind an
// explicit "Search all of Hugging Face (advanced)" button.

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/features/models_hub/state/recommended_models_provider.dart';
import 'package:dhruva/features/models_hub/ui/models_hub_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _fakeDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

Future<void> _pump(WidgetTester tester) async {
  // Tall surface so the whole curated ListView (cards + footer advanced-search
  // button) mounts — findsN* isn't scroll-aware.
  await tester.binding.setSurfaceSize(const Size(500, 4000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo)],
      child: MaterialApp(theme: AppTheme.dark, home: const ModelsHubScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('default tab is the curated catalog — no raw search field', (
    tester,
  ) async {
    await _pump(tester);

    // The value-stating header + a curated model appear by default.
    expect(find.text('Runs great on your phone'), findsOneWidget);
    expect(find.text(starterModelCatalog.first.displayName), findsOneWidget);
    // The raw HF firehose is NOT the default: no search field on this screen.
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('curated cards state their one-line "best for" and a size', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text(starterModelCatalog.first.bestFor), findsOneWidget);
  });

  testWidgets('raw HF search is demoted to an explicit advanced affordance', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Search all of Hugging Face (advanced)'), findsOneWidget);
  });
}
