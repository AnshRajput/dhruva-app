// "What moved" one-time sheet for upgrading users: shows once with three
// cards, persists the dismissal, and never shows on a fresh install.

import 'package:dhruva/core/settings/prefs_store.dart';
import 'package:dhruva/core/settings/what_moved.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_harness.dart';

void main() {
  test('copy covers the three moves', () {
    expect(whatMovedCards.map((c) => c.title), [
      'Chat is now Ask',
      'Models and Playground are in Settings',
      'Workflows are now Actions',
    ]);
  });

  testWidgets('upgrading user sees the sheet once, then never again', (
    tester,
  ) async {
    final prefs = MemoryPrefsStore(); // no dismissed flag: an upgrader
    await pumpDhruvaApp(tester, prefs: prefs);

    expect(find.byType(WhatMovedSheet), findsOneWidget);
    for (final card in whatMovedCards) {
      expect(find.text(card.title), findsOneWidget);
    }
    expect(prefs.values.containsKey('what_moved_dismissed'), isFalse);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.byType(WhatMovedSheet), findsNothing);
    expect(prefs.values['what_moved_dismissed'], 'true');

    // Relaunch (new app, same persisted store): no sheet.
    await tester.pumpWidget(const SizedBox());
    await pumpDhruvaApp(tester, prefs: prefs);
    expect(find.byType(WhatMovedSheet), findsNothing);
  });

  testWidgets('swiping the sheet away also counts as seen', (tester) async {
    final prefs = MemoryPrefsStore();
    await pumpDhruvaApp(tester, prefs: prefs);
    expect(find.byType(WhatMovedSheet), findsOneWidget);

    // Tap the scrim above the sheet to dismiss it.
    await tester.tapAt(const Offset(400, 20));
    await tester.pumpAndSettle();
    expect(find.byType(WhatMovedSheet), findsNothing);
    expect(prefs.values['what_moved_dismissed'], 'true');
  });

  testWidgets('already dismissed: never shown', (tester) async {
    await pumpDhruvaApp(
      tester,
      prefs: MemoryPrefsStore({'what_moved_dismissed': 'true'}),
    );
    expect(find.byType(WhatMovedSheet), findsNothing);
  });

  test(
    'pending provider: true until dismissed, then false and persisted',
    () async {
      final store = MemoryPrefsStore();
      final c = ProviderContainer(
        overrides: [prefsStoreProvider.overrideWith((ref) async => store)],
      );
      addTearDown(c.dispose);
      expect(await c.read(whatMovedPendingProvider.future), isTrue);
      await c.read(whatMovedPendingProvider.notifier).dismiss();
      expect(c.read(whatMovedPendingProvider).value, isFalse);
      expect(store.values[whatMovedDismissedKey], 'true');
    },
  );

  test('dismiss while build() is still loading is not overwritten', () async {
    // Slow prefs provider (the real one awaits a platform channel): build()
    // reads the absent flag and lands "pending" after dismiss() set state.
    final store = MemoryPrefsStore();
    final c = ProviderContainer(
      overrides: [
        prefsStoreProvider.overrideWith((ref) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return store;
        }),
      ],
    );
    addTearDown(c.dispose);
    await c.read(whatMovedPendingProvider.notifier).dismiss();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(c.read(whatMovedPendingProvider).value, isFalse);
    expect(store.values[whatMovedDismissedKey], 'true');
  });
}
