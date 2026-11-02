// iOS glass chrome runs content behind the app bar and tab bar, so scrollables
// that set their own padding must add the Scaffold inset back. Layout tests on
// the real screens (the blur-layer tests in platform_chrome_test can't see it).

import 'package:dhruva/core/widgets/next_step_card.dart' show QuietNextStep;
import 'package:dhruva/core/widgets/platform_chrome.dart' show AdaptiveTabBar;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_harness.dart';

void main() {
  Future<void> pumpIos(WidgetTester tester, String location) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pumpDhruvaApp(
      tester,
      location: location,
      surface: const Size(800, 700),
    );
  }

  // The override must be unset before the test body ends (invariant check).
  void resetPlatform() => debugDefaultTargetPlatformOverride = null;

  double barBottom(WidgetTester tester) =>
      tester.getBottomLeft(find.byType(AppBar)).dy;

  testWidgets('iOS Today: greeting starts below the glass app bar', (
    tester,
  ) async {
    await pumpIos(tester, '/today');
    final greeting = find.textContaining(RegExp(r'^(Good |Hello)'));
    expect(greeting, findsOneWidget);
    expect(
      tester.getTopLeft(greeting).dy,
      greaterThanOrEqualTo(barBottom(tester)),
    );
    resetPlatform();
  });

  testWidgets('iOS Library: first row clears the bar, last clears the tabs', (
    tester,
  ) async {
    await pumpIos(tester, '/library');
    final folder = find.byKey(const ValueKey('library-connect-folder'));
    expect(
      tester.getTopLeft(folder).dy,
      greaterThanOrEqualTo(barBottom(tester)),
    );

    await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    final lastCard = find.byType(QuietNextStep).last;
    expect(
      tester.getBottomLeft(lastCard).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(AdaptiveTabBar)).dy),
    );
    resetPlatform();
  });

  testWidgets('Android Today: bar is outside the body, no double inset', (
    tester,
  ) async {
    await pumpDhruvaApp(tester, surface: const Size(800, 700));
    final greeting = find.textContaining(RegExp(r'^(Good |Hello)'));
    expect(
      tester.getTopLeft(greeting).dy,
      greaterThanOrEqualTo(barBottom(tester)),
    );
  });
}
