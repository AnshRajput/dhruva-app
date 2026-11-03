// The Today quick-action pills are real touch targets (48 dp), centred, and
// visibly filled: `surface` on the page's own surface made them disappear.

import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/features/today/ui/quick_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('every pill is at least 48 dp tall, centred, and filled', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: QuickActionsRow()),
        ),
      ),
    );
    final scheme = Theme.of(
      tester.element(find.byType(QuickActionsRow)),
    ).colorScheme;
    for (final id in ['summarize', 'draft_reply', 'plan', 'files', 'all']) {
      final pill = find.byKey(ValueKey('today-action-$id'));
      expect(tester.getSize(pill).height, greaterThanOrEqualTo(48), reason: id);

      // The label sits on the pill's vertical centre.
      final label = tester.getCenter(
        find.descendant(of: pill, matching: find.byType(Row)),
      );
      expect(label.dy, closeTo(tester.getCenter(pill).dy, 0.5), reason: id);

      final deco =
          tester.widget<DecoratedBox>(pill).decoration as BoxDecoration;
      expect(deco.color, scheme.surfaceContainerHigh, reason: id);
      expect(deco.border, isNotNull, reason: id);
    }
  });
}
