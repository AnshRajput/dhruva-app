// Widget smoke test for the Loop-2 debug harness. Does NOT touch native code
// (no model is loaded), so it runs everywhere including CI.

import 'package:dhruva/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Debug chat screen renders its controls', (tester) async {
    await tester.pumpWidget(const DhruvaApp());

    expect(find.text('Dhruva · Engine Debug'), findsOneWidget);
    expect(find.text('Load'), findsOneWidget);
    expect(find.text('Generate'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('not loaded'), findsOneWidget);

    // Generate/Cancel are disabled until a model is loaded.
    final generate = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Generate'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(generate.onPressed, isNull);
  });
}
