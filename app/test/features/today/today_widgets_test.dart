// AttendeeLine never cuts a name in half; RouteTransitionGuard swallows taps
// while a route is still sliding in.

import 'dart:async';

import 'package:dhruva/core/widgets/route_transition_guard.dart';
import 'package:dhruva/features/today/ui/today_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AttendeeLine.fit', () {
    // 10 px per character keeps the arithmetic obvious.
    double w(String s) => s.length * 10.0;

    test('everyone fits: all names', () {
      expect(
        AttendeeLine.fit(['Ravi', 'Sana', 'Dev'], 200, w),
        'Ravi, Sana, Dev',
      );
    });

    test('cuts at name boundaries and counts the rest', () {
      final names = ['Ravi', 'Sana', 'Dev', 'Priya'];
      expect(AttendeeLine.fit(names, 200, w), 'Ravi, Sana, Dev +1');
      expect(AttendeeLine.fit(names, 140, w), 'Ravi, Sana +2');
      expect(AttendeeLine.fit(names, 80, w), 'Ravi +3');
      // Never a half name, never a bare "+N".
      final shape = RegExp(r'^Ravi(, Sana)?(, Dev)?(, Priya)?( \+\d)?$');
      for (var width = 30.0; width < 260; width += 7) {
        expect(shape.hasMatch(AttendeeLine.fit(names, width, w)), isTrue);
      }
    });

    test('one name, however long, is still shown (the Text ellipsizes)', () {
      expect(
        AttendeeLine.fit(['Alexandrina Montgomery'], 50, w),
        'Alexandrina Montgomery',
      );
      expect(AttendeeLine.fit([], 50, w), '');
    });
  });

  testWidgets('AttendeeLine in a narrow box shows whole names and +N', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 150,
            child: AttendeeLine(names: ['Ravi', 'Sana', 'Dev', 'Priya']),
          ),
        ),
      ),
    );
    final t = tester.widget<Text>(find.byType(Text)).data!;
    expect(t, anyOf('Ravi +3', 'Ravi, Sana +2', 'Ravi, Sana, Dev +1'));
  });

  group('RouteTransitionGuard', () {
    testWidgets('ignores taps until the pushed route has finished sliding', (
      tester,
    ) async {
      var taps = 0;
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: SizedBox()),
        ),
      );
      unawaited(
        nav.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => RouteTransitionGuard(
              child: Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => taps++,
                    child: const Text('Under the finger'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(); // route built, animation just started
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.text('Under the finger'), warnIfMissed: false);
      expect(taps, 0, reason: 'a tap during the transition must not land');

      await tester.pumpAndSettle();
      await tester.tap(find.text('Under the finger'));
      expect(taps, 1);
    });

    testWidgets('does nothing outside a route animation', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: RouteTransitionGuard(
            child: Scaffold(
              body: TextButton(
                onPressed: () => taps++,
                child: const Text('Go'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Go'));
      expect(taps, 1);
    });
  });
}
