/// WS7: the app-wide branded loader (`DhruvaLoader`) that replaced generic
/// `CircularProgressIndicator` spinners. Verifies it renders the star, keeps
/// breathing forever (indeterminate — bounded pump, never settles), and stays
/// within its calm opacity bounds so it can't flash to invisible.
library;

import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/core/theme/brand_star.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DhruvaLoader renders the brand star and animates forever', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(body: Center(child: DhruvaLoader(size: 32))),
      ),
    );
    // The star is present.
    expect(find.byType(DhruvaStar), findsOneWidget);

    // Indeterminate: it repeats, so a bounded pump advances it without ever
    // settling. Two samples 400ms apart land at different phases of the
    // breath, proving it's actually moving (not a static frame).
    await tester.pump();
    final opacity1 = tester.widget<Opacity>(find.byType(Opacity)).opacity;
    await tester.pump(const Duration(milliseconds: 400));
    final opacity2 = tester.widget<Opacity>(find.byType(Opacity)).opacity;
    expect(opacity1, isNot(equals(opacity2)));

    // Calm bounds: opacity never drops below the readable floor (0.45) nor
    // exceeds 1.0, whatever the phase.
    for (final o in [opacity1, opacity2]) {
      expect(o, greaterThanOrEqualTo(0.45));
      expect(o, lessThanOrEqualTo(1.0));
    }
  });

  testWidgets('DhruvaLoader shows an optional reassurance label', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: Center(child: DhruvaLoader(label: 'Loading…')),
        ),
      ),
    );
    expect(find.text('Loading…'), findsOneWidget);
  });
}
