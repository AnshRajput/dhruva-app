// Pure widget: verdict chips for all three ModelTier values, incl. the
// one-line RAM explanation (T5 test requirement).

import 'package:dhruva/core/device_info/model_tier.dart';
import 'package:dhruva/features/models_hub/widgets/verdict_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _gib = 1024 * 1024 * 1024;

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  testWidgets('comfortable tier shows the Comfortable label', (tester) async {
    await _pump(
      tester,
      const ModelVerdictChip(
        tier: ModelTier.comfortable,
        fileSizeBytes: 900 * 1024 * 1024, // 1B class, floor 4GB
        totalRamBytes: 8 * _gib,
      ),
    );
    expect(find.text('Comfortable'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('possible tier shows the Possible label + explanation', (
    tester,
  ) async {
    const chip = ModelVerdictChip(
      tier: ModelTier.possible,
      fileSizeBytes: 900 * 1024 * 1024, // 1B class, floor 4GB
      totalRamBytes: 4 * _gib,
    );
    await _pump(tester, chip);
    expect(find.text('Possible'), findsOneWidget);
    expect(find.byIcon(Icons.info), findsOneWidget);
    expect(chip.explanation, 'needs ~4GB RAM, you have 4GB');
  });

  testWidgets('notRecommended tier shows the Not recommended label', (
    tester,
  ) async {
    await _pump(
      tester,
      const ModelVerdictChip(
        tier: ModelTier.notRecommended,
        fileSizeBytes: 2 * _gib, // 3-4B class, floor 6GB
        totalRamBytes: 3 * _gib,
      ),
    );
    expect(find.text('Not recommended'), findsOneWidget);
    expect(find.byIcon(Icons.warning), findsOneWidget);
  });
}
