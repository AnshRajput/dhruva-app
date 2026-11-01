// Wave 1 placeholder surfaces (Today, Inbox, Library, timeline, connectors):
// they match the comps' structure and every empty state ends in a working
// next action (no dead ends).

import 'package:dhruva/core/crash/crash_log.dart';
import 'package:dhruva/core/router/app_router.dart';
import 'package:dhruva/core/settings/prefs_store.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/features/today/state/day_text.dart';
import 'package:dhruva/features/today/ui/today_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_harness.dart';

void main() {
  group('day text', () {
    test('formats the date and greeting', () {
      expect(formatDayLine(DateTime(2026, 11, 2)), 'Monday 2 November');
      expect(greetingFor(DateTime(2026, 11, 2, 7)), 'Good morning');
      expect(greetingFor(DateTime(2026, 11, 2, 14)), 'Good afternoon');
      expect(greetingFor(DateTime(2026, 11, 2, 21)), 'Good evening');
    });
  });

  group('Today', () {
    testWidgets('has the comp structure: header, brief, quick actions, '
        'Up next + See day, inbox card', (tester) async {
      await pumpDhruvaApp(tester);
      expect(find.text('Dhruva'), findsOneWidget); // wordmark from AppIdentity
      expect(find.byKey(const ValueKey('today-settings')), findsOneWidget);
      expect(find.byKey(const ValueKey('today-brief')), findsOneWidget);
      expect(
        find.text('Your brief appears here once you connect your calendar.'),
        findsOneWidget,
      );
      for (final id in ['summarize', 'draft_reply']) {
        expect(find.byKey(ValueKey('today-action-$id')), findsOneWidget);
      }
      expect(find.text('Up next'), findsOneWidget);
      expect(find.byKey(const ValueKey('today-see-day')), findsOneWidget);
      expect(find.text('Set up your inbox'), findsOneWidget);
    });

    testWidgets('greeting and date come from the injected clock', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            prefsStoreProvider.overrideWith((ref) async => MemoryPrefsStore()),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: TodayScreen(now: DateTime(2026, 11, 2, 7)),
          ),
        ),
      );
      expect(find.text('Good morning'), findsOneWidget);
      expect(find.text('Monday 2 November'), findsOneWidget);
    });

    testWidgets(
      'crash-report nudge (formerly on the Chats home) shows on Today',
      (tester) async {
        await pumpDhruvaApp(
          tester,
          overrides: [
            unseenCrashReportsProvider.overrideWith(
              (ref) async => [
                CrashRecord(
                  timestamp: DateTime.utc(2026, 11, 1),
                  appVersion: '0.6.1',
                  appBuild: '105',
                  platform: 'android',
                  osVersion: '15',
                  errorType: 'StateError',
                  message: 'boom',
                  stack: '',
                ),
              ],
            ),
          ],
        );
        expect(find.byKey(const ValueKey('crash-banner')), findsOneWidget);
      },
    );

    testWidgets('gear opens Settings full-screen', (tester) async {
      await pumpDhruvaApp(tester);
      await tester.tap(find.byKey(const ValueKey('today-settings')));
      await tester.pumpAndSettle();
      // The big serif page title (the app bar itself carries only Back).
      expect(find.text('Settings'), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-about-me')), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('quick action "Draft reply" opens that Action', (tester) async {
      await pumpDhruvaApp(tester);
      await tester.tap(find.byKey(const ValueKey('today-action-draft_reply')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Actions'), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('"All actions" opens the Actions list', (tester) async {
      await pumpDhruvaApp(tester);
      // The row scrolls horizontally; bring the last chip into view.
      await tester.drag(
        find.byKey(const ValueKey('today-quick-actions')),
        const Offset(-1200, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('today-action-all')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Actions'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('"Summarize clipboard" carries clipboard text into Actions', (
      tester,
    ) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.getData'
            ? <String, dynamic>{'text': 'Meeting moved to 4pm'}
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpDhruvaApp(tester);
      await tester.tap(find.byKey(const ValueKey('today-action-summarize')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Actions'), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Meeting moved to 4pm'), findsWidgets);
    });

    testWidgets('"See day" opens the empty timeline, which has an action', (
      tester,
    ) async {
      await pumpDhruvaApp(tester);
      await tester.tap(find.byKey(const ValueKey('today-see-day')));
      await tester.pumpAndSettle();
      expect(find.text('Nothing on your day yet'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('day-connect-calendar')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Connectors'), findsOneWidget);
    });

    testWidgets('"Set up inbox" opens Inbox full-screen, with a back button', (
      tester,
    ) async {
      await pumpDhruvaApp(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('today-setup-inbox')),
      );
      await tester.tap(find.byKey(const ValueKey('today-setup-inbox')));
      await tester.pumpAndSettle();
      expect(find.text('Your inbox, in one calm list'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(BackButton), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Your brief'), findsOneWidget);
    });

    testWidgets('brief and Up next both lead to the connect screen', (
      tester,
    ) async {
      for (final key in ['today-brief-connect', 'today-connect-calendar']) {
        await pumpDhruvaApp(tester);
        await tester.ensureVisible(find.byKey(ValueKey(key)));
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(AppBar, 'Connectors'), findsOneWidget);
      }
    });
  });

  group('Connectors placeholder', () {
    testWidgets('is never a dead end: Ask and Actions both work', (
      tester,
    ) async {
      await pumpDhruvaApp(tester, location: '/settings/connectors');
      expect(find.text('Calendar'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('connectors-open-actions')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Actions'), findsOneWidget);

      await pumpDhruvaApp(tester, location: '/settings/connectors');
      await tester.tap(find.byKey(const ValueKey('connectors-open-ask')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Personas'), findsOneWidget);
    });
  });

  group('Library', () {
    testWidgets('always has Documents, Saved and To-dos with next steps', (
      tester,
    ) async {
      await pumpDhruvaApp(tester, location: '/library');
      for (final section in ['Documents', 'Saved', 'To-dos']) {
        expect(find.text(section), findsOneWidget);
      }
      expect(
        find.byKey(const ValueKey('library-connect-folder')),
        findsOneWidget,
      );
      expect(find.text('Connect a folder'), findsOneWidget);
      for (final key in [
        'library-documents-action',
        'library-saved-action',
        'library-todos-action',
      ]) {
        final btn = find.byKey(ValueKey(key));
        expect(btn, findsOneWidget, reason: key);
        expect(tester.widget<FilledButton>(btn).onPressed, isNotNull);
      }
    });

    testWidgets('folder row leads to the connect placeholder', (tester) async {
      await pumpDhruvaApp(tester, location: '/library');
      await tester.tap(find.byKey(const ValueKey('library-connect-folder')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Connectors'), findsOneWidget);
    });

    testWidgets('Documents action opens the document Action', (tester) async {
      await pumpDhruvaApp(tester, location: '/library');
      await tester.tap(find.byKey(const ValueKey('library-documents-action')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Actions'), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('To-dos action opens Extract to-dos', (tester) async {
      await pumpDhruvaApp(tester, location: '/library');
      await tester.tap(find.byKey(const ValueKey('library-todos-action')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Actions'), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('Saved action goes to Ask', (tester) async {
      await pumpDhruvaApp(tester, location: '/library');
      await tester.tap(find.byKey(const ValueKey('library-saved-action')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Personas'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
    });
  });

  group('Inbox', () {
    testWidgets('empty connect state has a working action', (tester) async {
      await pumpDhruvaApp(tester, location: '/inbox');
      expect(find.text('Your inbox, in one calm list'), findsOneWidget);
      final action = find.byKey(const ValueKey('inbox-connect'));
      expect(tester.widget<FilledButton>(action).onPressed, isNotNull);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Connectors'), findsOneWidget);
    });
  });

  testWidgets('Ask keeps Actions and Personas one tap away', (tester) async {
    await pumpDhruvaApp(tester, location: '/ask');
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Actions'), findsOneWidget);
    appRouter.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Personas'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Personas'), findsOneWidget);
  });
}
