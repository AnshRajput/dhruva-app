// Today, against the real connector hub over an in-memory database: the brief
// (cited phrases, dropped sentences, cache, no-model fallback), the connect and
// permission-denied flows, Up next + Prep, Needs you, the digest and the quick
// actions.

import 'dart:async';
import 'dart:convert';

import 'package:dhruva/core/device_health/device_health.dart';
import 'package:dhruva/core/settings/prefs_store.dart';
import 'package:dhruva/data/connectors/connector.dart';
import 'package:dhruva/data/connectors/connector_sources.dart';
import 'package:dhruva/features/today/state/brief_cache.dart';
import 'package:dhruva/features/today/state/brief_facts.dart';
import 'package:dhruva/features/today/state/brief_writer.dart';
import 'package:dhruva/features/today/ui/day_timeline_screen.dart';
import 'package:dhruva/features/today/ui/today_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_connector_sources.dart';
import 'today_fixtures.dart';
import 'today_harness.dart';

Future<void> _seedDay(TodayHarness h) async {
  await h.seedCalendar();
  await h.seedNotifications([raviMessage, ...swiggyPings, ...hdfcPings]);
}

String _freshCache() => jsonEncode(
  WrittenBrief(
    writtenAt: at(7, 2),
    raw: 'Design sync is at 9:30 [1].',
    facts: const [
      BriefFact(
        n: 1,
        kind: FactKind.event,
        text: 'Design sync at 9:30.',
        ref: 'event:1',
      ),
    ],
  ).toJson(),
);

/// The chips scroll sideways and build lazily: bring [id] on screen.
Future<void> _revealAction(WidgetTester tester, String id) async {
  await tester.dragUntilVisible(
    find.byKey(ValueKey('today-action-$id')),
    find.byKey(const ValueKey('today-quick-actions')),
    const Offset(-120, 0),
  );
  await settle(tester);
}

void main() {
  group('header', () {
    todayTest('greets by name, shows the date and real counts', (tester) async {
      await pumpToday(
        tester,
        prefs: MemoryPrefsStore({
          'user_profile': jsonEncode({'name': 'Meera Menon'}),
        }),
        seed: _seedDay,
      );
      expect(find.text('Good morning, Meera'), findsOneWidget);
      expect(
        find.text('Monday 2 November · 2 meetings · 1 reply waiting'),
        findsOneWidget,
      );
      expect(find.text('Dhruva'), findsOneWidget); // wordmark via AppIdentity
    });

    todayTest('no name set: plain greeting', (tester) async {
      await pumpToday(tester, seed: _seedDay);
      expect(find.text('Good morning'), findsOneWidget);
    });
  });

  group('calendar not connected', () {
    todayTest('the brief card is a one-tap connect; tapping connects and '
        'shows the day', (tester) async {
      final h = await pumpToday(tester);
      h.kit.calendar.items = [
        calEvent('e1', title: 'Design sync', start: at(9, 30)),
      ];
      expect(find.text('Connect your calendar'), findsWidgets);
      expect(find.text('Up next'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('today-brief-connect')));
      await settle(tester);

      expect(h.kit.calendar.requests, 1);
      expect(find.text('Up next'), findsOneWidget);
      expect(find.text('Design sync'), findsWidgets);
    });

    todayTest('permission denied: says so and offers Open settings', (
      tester,
    ) async {
      final h = await pumpToday(tester);
      h.kit.calendar.afterRequest = DevicePermission.denied;
      await tester.tap(find.byKey(const ValueKey('today-brief-connect')));
      await settle(tester);

      expect(find.text('Calendar access is off'), findsOneWidget);
      expect(find.text('Up next'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('today-brief-open-settings')));
      await settle(tester);
      expect(h.kit.calendar.settingsOpened, 1);
    });

    todayTest('a permission switched off later shows the same fix', (
      tester,
    ) async {
      final h = await pumpToday(tester, seed: (h) => h.seedCalendar());
      expect(find.text('Up next'), findsOneWidget);
      h.kit.calendar.perm = DevicePermission.denied;
      await h.kit.hub.calendar.refreshStatus();
      await settle(tester);
      expect(find.text('Calendar access is off'), findsOneWidget);
    });
  });

  group('brief: no model', () {
    todayTest('shows the facts as a plain list and offers Get a model', (
      tester,
    ) async {
      final h = await pumpToday(
        tester,
        writer: FakeBriefWriter(model: BriefModelStatus.none),
        seed: _seedDay,
      );
      expect(find.text('Your day, at a glance'), findsOneWidget);
      expect(find.textContaining('Design sync at 9:30'), findsWidgets);
      expect(
        find.textContaining('Ravi Menon messaged on WhatsApp'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('today-brief-get-model')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('today-brief-write')), findsNothing);
      expect(h.writer.prompts, isEmpty); // nothing was written
      await tester.tap(find.byKey(const ValueKey('today-brief-get-model')));
      await settle(tester);
      expect(h.visited, contains('/settings/models'));
    });

    todayTest('a fact is tappable and opens its source', (tester) async {
      await pumpToday(
        tester,
        writer: FakeBriefWriter(model: BriefModelStatus.none),
        seed: _seedDay,
      );
      await tester.tap(find.byKey(const ValueKey('fact-1')));
      await settle(tester);
      expect(find.byKey(const ValueKey('event-sheet-title')), findsOneWidget);
    });
  });

  group('brief: written', () {
    todayTest('writes on open, cites facts, drops uncited sentences', (
      tester,
    ) async {
      final h = await pumpToday(
        tester,
        writer: FakeBriefWriter(
          output:
              'Design sync is at 9:30 [1]. Ravi Menon messaged you [4]. '
              'Everything will be wonderful today.',
        ),
        seed: _seedDay,
      );
      expect(h.writer.prompts, hasLength(1));
      final text = tester
          .widget<RichText>(
            find.descendant(
              of: find.byKey(const ValueKey('today-brief-text')),
              matching: find.byType(RichText),
            ),
          )
          .text
          .toPlainText();
      expect(text, contains('Design sync is at 9:30.'));
      expect(text, isNot(contains('wonderful')));
      expect(
        find.textContaining('Written on this phone at 7:42 AM'),
        findsOneWidget,
      );
      // The prompt carried the facts inside one sources block.
      expect(h.writer.prompts.single, contains('\n<sources>\n[1] '));
    });

    todayTest('tapping a cited phrase opens its source', (tester) async {
      await pumpToday(tester, seed: _seedDay);
      await tester.tapAt(
        tester.getTopLeft(find.byKey(const ValueKey('today-brief-text'))) +
            const Offset(12, 10),
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('event-sheet-title')), findsOneWidget);
      expect(find.text('Design sync'), findsWidgets);
    });

    todayTest('"How this was written" lists the numbered facts', (
      tester,
    ) async {
      await pumpToday(tester, seed: _seedDay);
      expect(find.byKey(const ValueKey('today-brief-facts')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('today-brief-how')));
      await settle(tester);
      expect(find.byKey(const ValueKey('today-brief-facts')), findsOneWidget);
      expect(find.byKey(const ValueKey('fact-1')), findsOneWidget);
    });

    todayTest('a fresh cached brief is shown without writing a new one', (
      tester,
    ) async {
      final h = await pumpToday(
        tester,
        prefs: MemoryPrefsStore({'today_brief_v1': _freshCache()}),
        seed: _seedDay,
      );
      expect(h.writer.prompts, isEmpty);
      expect(
        find.textContaining('Written on this phone at 7:02 AM'),
        findsOneWidget,
      );
    });

    todayTest('a stale cached brief (older than 3 h) is rewritten on open', (
      tester,
    ) async {
      final stale = jsonEncode(
        WrittenBrief(
          writtenAt: at(3, 30),
          raw: 'Old news [1].',
          facts: const [
            BriefFact(n: 1, kind: FactKind.event, text: 'x', ref: 'event:1'),
          ],
        ).toJson(),
      );
      final h = await pumpToday(
        tester,
        prefs: MemoryPrefsStore({'today_brief_v1': stale}),
        seed: _seedDay,
      );
      expect(h.writer.prompts, hasLength(1));
      expect(find.textContaining('Old news'), findsNothing);
    });

    todayTest('regenerate writes again and caches the new brief', (
      tester,
    ) async {
      final h = await pumpToday(tester, seed: _seedDay);
      expect(h.writer.prompts, hasLength(1));
      h.writer.output = 'Budget review is at 11:00 [2].';
      await tester.tap(find.byKey(const ValueKey('today-brief-regenerate')));
      await settle(tester);
      expect(h.writer.prompts, hasLength(2));
      expect(find.textContaining('Budget review is at 11:00.'), findsWidgets);
      final cached = jsonDecode(h.prefs.values['today_brief_v1']!) as Map;
      expect(cached['raw'], 'Budget review is at 11:00 [2].');
      expect((cached['facts'] as List), isNotEmpty);
    });

    todayTest('pull to refresh rewrites the brief', (tester) async {
      final h = await pumpToday(tester, seed: _seedDay);
      expect(h.writer.prompts, hasLength(1));
      // The same callback a pull runs (the drag gesture itself is the
      // framework's, and is exercised on a device).
      unawaited(
        tester
            .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
            .show(),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(h.writer.prompts, hasLength(2));
    });

    todayTest('a low battery holds back the unasked write; the button '
        'still works', (tester) async {
      final h = await pumpToday(
        tester,
        writer: FakeBriefWriter(model: BriefModelStatus.idle),
        seed: _seedDay,
        health: const DeviceHealth(batteryPercent: 3),
      );
      expect(h.writer.prompts, isEmpty);
      expect(h.writer.prepares, 0);
      await tester.tap(find.byKey(const ValueKey('today-brief-write')));
      await settle(tester);
      expect(h.writer.prepares, 1); // the model was loaded on request
      expect(h.writer.prompts, hasLength(1));
      expect(find.byKey(const ValueKey('today-brief-text')), findsOneWidget);
    });

    todayTest('a model that cannot be reached shows the fix, keeps facts', (
      tester,
    ) async {
      final h = await pumpToday(
        tester,
        writer: FakeBriefWriter()
          ..failWith = const BriefUnavailable(
            'Your phone is busy with another task. Pull down to try again.',
          ),
        seed: _seedDay,
      );
      expect(h.writer.prompts, hasLength(1));
      expect(find.byKey(const ValueKey('today-brief-error')), findsOneWidget);
      expect(find.text('Your day, at a glance'), findsOneWidget);
    });

    todayTest('model text with no valid citation is dropped, not shown', (
      tester,
    ) async {
      await pumpToday(
        tester,
        writer: FakeBriefWriter(output: 'A lovely day ahead [9].'),
        seed: _seedDay,
      );
      expect(find.textContaining('lovely'), findsNothing);
      expect(find.byKey(const ValueKey('today-brief-error')), findsOneWidget);
      expect(find.text('Your day, at a glance'), findsOneWidget);
    });

    todayTest('disconnecting a source forgets what was written from it', (
      tester,
    ) async {
      final h = await pumpToday(
        tester,
        prefs: MemoryPrefsStore({'today_brief_v1': _freshCache()}),
      );
      // The calendar was never connected here, so the cached brief (which
      // quotes an event) must be erased, not shown.
      expect(find.byKey(const ValueKey('today-brief-text')), findsNothing);
      expect(h.prefs.values['today_brief_v1'], '');
    });
  });

  group('Up next', () {
    todayTest('shows the next events, "in 1h 48m", attendees; Prep opens '
        'Ask with sources pinned', (tester) async {
      final h = await pumpToday(
        tester,
        writer: FakeBriefWriter(model: BriefModelStatus.none),
        seed: _seedDay,
      );
      expect(find.byKey(const ValueKey('up-next-title')), findsOneWidget);
      expect(find.text('in 1h 48m'), findsOneWidget);
      expect(find.text('Ravi, Sana, Dev'), findsOneWidget);
      expect(
        find.textContaining('Budget review', findRichText: true),
        findsWidgets,
      );
      expect(find.textContaining('Room 4B', findRichText: true), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('up-next-prep')));
      await settle(tester);
      final uri = Uri.parse(h.visited.single);
      expect(uri.path, '/chat/new');
      expect(
        uri.queryParameters['prompt'],
        'Prep me for my 9:30 AM meeting: who is attending, what do I know '
        'about them, and any related notes.',
      );
      expect(uri.queryParameters['sources'], 'calendar,contacts,folder');
      expect(int.tryParse(uri.queryParameters['event']!), isNotNull);
      // The event's own (untrusted) title never rides in the prompt.
      expect(uri.queryParameters['prompt'], isNot(contains('Design sync')));
    });

    todayTest('tapping the event opens a read-only sheet with Open in '
        'calendar', (tester) async {
      final h = await pumpToday(
        tester,
        writer: FakeBriefWriter(model: BriefModelStatus.none),
        seed: _seedDay,
      );
      await tester.tap(find.byKey(const ValueKey('up-next-title')));
      await settle(tester);
      expect(find.byKey(const ValueKey('event-sheet-title')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(EventSheet),
          matching: find.text('Google Meet'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('event-open-calendar')));
      await settle(tester);
      expect(h.openedCalendarAt, [at(9, 30)]);
    });

    todayTest('attendee names come from the contacts connector', (
      tester,
    ) async {
      await pumpToday(
        tester,
        writer: FakeBriefWriter(model: BriefModelStatus.none),
        seed: (h) async {
          h.kit.contacts.byAddress['ravi@x.test'] = const DeviceContact(
            id: 'c1',
            name: 'Ravi Menon',
          );
          await h.kit.hub.contacts.connect();
          await h.seedCalendar();
          await h.kit.hub.sync.refresh();
        },
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('up-next-card')),
          matching: find.textContaining('Ravi Menon, Sana, Dev'),
        ),
        findsOneWidget,
      );
    });

    todayTest('a calendar with nothing coming up says so, with an action', (
      tester,
    ) async {
      final h = await pumpToday(
        tester,
        writer: FakeBriefWriter(model: BriefModelStatus.none),
        seed: (h) async {
          await h.kit.hub.calendar.connect();
          await h.kit.hub.sync.refresh();
        },
      );
      expect(find.text('Nothing coming up'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('up-next-open-calendar')));
      await settle(tester);
      expect(h.openedCalendarAt, hasLength(1));
    });

    todayTest('a failed sync names the fix and offers Try again', (
      tester,
    ) async {
      await pumpToday(
        tester,
        writer: FakeBriefWriter(model: BriefModelStatus.none),
        seed: (h) async {
          await h.seedCalendar();
          h.kit.calendar.failRead = true;
          try {
            await h.kit.hub.calendar.sync();
          } on ConnectorException {
            // expected: the status now needs attention
          }
        },
      );
      expect(find.byKey(const ValueKey('up-next-attention')), findsOneWidget);
      expect(find.byKey(const ValueKey('up-next-retry')), findsOneWidget);
    });

    todayTest('says "last synced" so offline reads as honest', (tester) async {
      await pumpToday(
        tester,
        writer: FakeBriefWriter(model: BriefModelStatus.none),
        seed: _seedDay,
      );
      expect(find.byKey(const ValueKey('up-next-synced')), findsOneWidget);
    });
  });

  group('Needs you and the digest', () {
    todayTest('Needs you lists people-messages and opens a sheet with '
        'Draft reply', (tester) async {
      final h = await pumpToday(
        tester,
        writer: FakeBriefWriter(model: BriefModelStatus.none),
        seed: _seedDay,
      );
      expect(find.text('Needs you'), findsOneWidget);
      expect(find.text('1 waiting'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('needs-you-0')));
      await settle(tester);
      expect(
        find.byKey(const ValueKey('notification-sheet-title')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('notification-draft-reply')));
      await settle(tester);
      final uri = Uri.parse(h.visited.single);
      expect(uri.path, '/actions');
      expect(uri.queryParameters['id'], 'draft_reply');
      expect(uri.queryParameters['text'], startsWith('Ravi Menon: Wants'));
    });

    todayTest('the section is hidden when nothing needs you', (tester) async {
      await pumpToday(
        tester,
        writer: FakeBriefWriter(model: BriefModelStatus.none),
        seed: (h) async {
          await h.seedCalendar();
          await h.seedNotifications(hdfcPings);
        },
      );
      expect(find.text('Needs you'), findsNothing);
    });

    todayTest('digest: grouped by app, Mark all read hides it (local flag)', (
      tester,
    ) async {
      final h = await pumpToday(
        tester,
        writer: FakeBriefWriter(model: BriefModelStatus.none),
        seed: _seedDay,
      );
      expect(find.byKey(const ValueKey('today-digest')), findsOneWidget);
      expect(find.text('7 notifications'), findsOneWidget);
      expect(find.textContaining('Swiggy', findRichText: true), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('digest-mark-read')));
      await settle(tester);
      expect(find.byKey(const ValueKey('today-digest')), findsNothing);
      expect(h.prefs.values['notifications_read_at'], isNotNull);
    });

    todayTest('iOS: no digest and no Needs you (notifications are '
        'unsupported)', (tester) async {
      await pumpToday(
        tester,
        notificationsSupported: false,
        writer: FakeBriefWriter(model: BriefModelStatus.none),
        seed: (h) => h.seedCalendar(),
      );
      expect(find.byKey(const ValueKey('today-digest')), findsNothing);
      expect(find.text('Needs you'), findsNothing);
    });

    todayTest('notification access switched off: names the fix', (
      tester,
    ) async {
      final h = await pumpToday(
        tester,
        writer: FakeBriefWriter(model: BriefModelStatus.none),
        seed: (h) async {
          await h.seedCalendar();
          await h.seedNotifications(hdfcPings);
          h.kit.notifications.granted = false;
          await h.kit.hub.notifications.refreshStatus();
        },
      );
      expect(find.byKey(const ValueKey('digest-attention')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('digest-open-settings')));
      await settle(tester);
      expect(h.kit.notifications.settingsOpened, 1);
    });
  });

  group('quick actions', () {
    todayTest('Plan my day opens Ask with the calendar pinned', (tester) async {
      final h = await pumpToday(
        tester,
        writer: FakeBriefWriter(model: BriefModelStatus.none),
        seed: (h) => h.seedCalendar(),
      );
      await _revealAction(tester, 'plan');
      await tester.tap(find.byKey(const ValueKey('today-action-plan')));
      await settle(tester);
      final uri = Uri.parse(h.visited.single);
      expect(uri.path, '/chat/new');
      expect(uri.queryParameters['sources'], 'calendar');
      expect(uri.queryParameters['prompt'], startsWith('Plan my day'));
    });

    todayTest('Plan my day without a calendar sends you to connect it', (
      tester,
    ) async {
      final h = await pumpToday(tester);
      await _revealAction(tester, 'plan');
      await tester.tap(find.byKey(const ValueKey('today-action-plan')));
      await settle(tester);
      expect(
        find.textContaining('Connect your calendar first'),
        findsOneWidget,
      );
      expect(h.visited, ['/settings/connectors']);
    });

    todayTest('Ask my files pins the folder once it is connected', (
      tester,
    ) async {
      final h = await pumpToday(
        tester,
        writer: FakeBriefWriter(model: BriefModelStatus.none),
        seed: (h) async {
          await h.seedCalendar();
          h.kit.folder.nextPick = const FolderGrant(id: 'g', name: 'Notes');
          await h.kit.hub.folder.connect();
        },
      );
      await _revealAction(tester, 'files');
      await tester.tap(find.byKey(const ValueKey('today-action-files')));
      await settle(tester);
      final uri = Uri.parse(h.visited.single);
      expect(uri.path, '/chat/new');
      expect(uri.queryParameters['sources'], 'folder');
    });

    todayTest('Draft reply carries the clipboard into Actions', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.getData'
            ? <String, dynamic>{'text': 'Can you send the invoice?'}
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final h = await pumpToday(tester);
      await _revealAction(tester, 'draft_reply');
      await tester.tap(find.byKey(const ValueKey('today-action-draft_reply')));
      await settle(tester);
      final uri = Uri.parse(h.visited.single);
      expect(uri.path, '/actions');
      expect(uri.queryParameters['id'], 'draft_reply');
      expect(uri.queryParameters['text'], 'Can you send the invoice?');
    });
  });

  group('timeline', () {
    todayTest('events and notification groups on one rail, with now', (
      tester,
    ) async {
      await pumpToday(
        tester,
        writer: FakeBriefWriter(model: BriefModelStatus.none),
        seed: _seedDay,
      );
      await tester.tap(find.byKey(const ValueKey('today-see-day')));
      await settle(tester);
      expect(find.text('Monday 2 November'), findsWidgets);
      expect(
        find.byKey(const ValueKey('timeline-now-caption')),
        findsOneWidget,
      );
      expect(find.text('Free until 9:30'), findsOneWidget);
      final design = tester.getTopLeft(find.text('Design sync')).dy;
      final budget = tester.getTopLeft(find.text('Budget review')).dy;
      final now = tester.getTopLeft(find.text('Free until 9:30')).dy;
      final ravi = tester.getTopLeft(find.textContaining('Wants your OK')).dy;
      expect(ravi, lessThan(now)); // 7:12 is before now (7:42)
      expect(now, lessThan(design));
      expect(design, lessThan(budget));
    });

    todayTest('empty day: a clear day with an action', (tester) async {
      final h = await pumpToday(
        tester,
        writer: FakeBriefWriter(model: BriefModelStatus.none),
        seed: (h) async {
          await h.kit.hub.calendar.connect();
        },
      );
      await tester.tap(find.byKey(const ValueKey('today-see-day')));
      await settle(tester);
      expect(find.text('A clear day'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('day-open-calendar')));
      await settle(tester);
      expect(h.openedCalendarAt, hasLength(1));
    });

    todayTest('calendar off: the timeline offers to connect it', (
      tester,
    ) async {
      final h = await pumpToday(tester, home: const DayTimelineScreen());
      expect(find.text('Nothing on your day yet'), findsOneWidget);
      h.kit.calendar.afterRequest = DevicePermission.denied;
      await tester.tap(find.byKey(const ValueKey('day-connect-calendar')));
      await settle(tester);
      // Refused: land where the fix is shown.
      expect(h.visited, ['/settings/connectors']);
    });
  });
}
