// Rule 6 platform chrome: iOS gets the translucent tab bar APPROXIMATION
// (BackdropFilter over a translucent fill) on chrome only, with a
// reduce-transparency fallback; Android keeps solid Material 3 chrome.

import 'package:dhruva/core/settings/prefs_store.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/core/theme/appearance_providers.dart';
import 'package:dhruva/core/widgets/platform_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldUseGlass', () {
    test('only iOS, and only without high contrast or the app switch', () {
      bool g(TargetPlatform p, {bool hc = false, bool reduce = false}) =>
          shouldUseGlass(
            platform: p,
            highContrast: hc,
            reduceTransparencySetting: reduce,
          );
      expect(g(TargetPlatform.iOS), isTrue);
      expect(g(TargetPlatform.iOS, hc: true), isFalse);
      expect(g(TargetPlatform.iOS, reduce: true), isFalse);
      expect(g(TargetPlatform.android), isFalse);
      expect(g(TargetPlatform.android, hc: false, reduce: false), isFalse);
    });
  });

  Widget bar(
    TargetPlatform platform, {
    bool highContrast = false,
    bool reduce = false,
  }) {
    return ProviderScope(
      overrides: [
        prefsStoreProvider.overrideWith(
          (ref) async => MemoryPrefsStore({'reduce_transparency': '$reduce'}),
        ),
      ],
      child: MediaQuery(
        data: MediaQueryData(highContrast: highContrast),
        child: MaterialApp(
          theme: AppTheme.dark.copyWith(platform: platform),
          home: Scaffold(
            bottomNavigationBar: AdaptiveTabBar(
              selectedIndex: 0,
              onSelected: (_) {},
              destinations: const [
                NavigationDestination(icon: Icon(Icons.sunny), label: 'Today'),
                NavigationDestination(icon: Icon(Icons.chat), label: 'Ask'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Finder blur() => find.descendant(
    of: find.byType(AdaptiveTabBar),
    matching: find.byType(BackdropFilter),
  );

  testWidgets('iOS: tab bar is a translucent blur layer', (tester) async {
    await tester.pumpWidget(bar(TargetPlatform.iOS));
    await tester.pumpAndSettle();
    expect(blur(), findsOneWidget);
    // No pill on iOS: Cupertino tab bars tint the icon instead.
    final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(nav.indicatorColor, Colors.transparent);
  });

  testWidgets('iOS + Increase Contrast: solid fallback, no blur', (
    tester,
  ) async {
    await tester.pumpWidget(bar(TargetPlatform.iOS, highContrast: true));
    await tester.pumpAndSettle();
    expect(blur(), findsNothing);
  });

  testWidgets('iOS + app reduce-transparency setting: solid, no blur', (
    tester,
  ) async {
    await tester.pumpWidget(bar(TargetPlatform.iOS, reduce: true));
    await tester.pumpAndSettle();
    expect(blur(), findsNothing);
  });

  testWidgets('Android: solid Material chrome with the pill indicator', (
    tester,
  ) async {
    await tester.pumpWidget(bar(TargetPlatform.android));
    await tester.pumpAndSettle();
    expect(blur(), findsNothing);
    final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(nav.indicatorColor, isNull); // theme supplies the pill
    expect(
      Theme.of(
        tester.element(find.byType(NavigationBar)),
      ).navigationBarTheme.indicatorShape,
      isA<StadiumBorder>(),
    );
  });

  testWidgets('reduceTransparencyProvider defaults off', (tester) async {
    final c = ProviderContainer(
      overrides: [
        prefsStoreProvider.overrideWith((ref) async => MemoryPrefsStore()),
      ],
    );
    addTearDown(c.dispose);
    expect(await c.read(reduceTransparencyProvider.future), isFalse);
  });
}
