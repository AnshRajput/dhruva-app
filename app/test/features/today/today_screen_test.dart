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
import 'package:dhruva/data/downloads/download_manager.dart';
import 'package:dhruva/features/today/state/brief_cache.dart';
import 'package:dhruva/features/today/state/brief_facts.dart';
import 'package:dhruva/features/today/state/brief_writer.dart';
import 'package:dhruva/features/today/ui/day_timeline_screen.dart';
import 'package:dhruva/features/today/ui/today_sheets.dart';
import 'package:dhruva/features/today/ui/today_widgets.dart';
import 'package:flutter/gestures.dart';
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

/// The brief's sentences as plain text.
String _briefText(WidgetTester tester) => tester
    .widget<RichText>(
      find.descendant(
        of: find.byKey(const ValueKey('today-brief-text')),
        matching: find.byType(RichText),
      ),
    )
    .text
    .toPlainText();

/// Taps the cited phrase containing [containing], the way a finger on it
/// would (the span's own tap recognizer).
Future<void> _tapCited(WidgetTester tester, String containing) async {
  final rich = tester.widget<RichText>(
    find.descendant(
      of: find.byKey(const ValueKey('today-brief-text')),
      matching: find.byType(RichText),
    ),
  );
  TapGestureRecognizer? found;
  rich.text.visitChildren((s) {
    if (s is TextSpan &&
        s.recognizer is TapGestureRecognizer &&
        (s.text ?? '').contains(containing)) {
      found = s.recognizer! as TapGestureRecognizer;
      return false;
    }
    return true;
  });
  expect(found, isNotNull, reason: 'no cited phrase "$containing"');
  found!.onTap!();
  await settle(tester);
}

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

    todayTest('first Deny: retry sentence, Connect stays; second Deny: Open '
        'settings', (tester) async {
      final h = await pumpToday(tester);
      // Android's first Deny: the system will still ask.
      h.kit.calendar.afterRequest = DevicePermission.notDetermined;
      await tester.tap(find.byKey(const ValueKey('today-brief-connect')));
      await settle(tester);

      expect(
        find.textContaining(
          "Calendar wasn't allowed. Tap Connect to try again",
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('today-brief-connect')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('today-brief-open-settings')),
        findsNothing,
      );
      expect(find.text('Up next'), findsNothing);

      // A resume does not wipe the sentence.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(find.textContaining("Calendar wasn't allowed"), findsOneWidget);

      // Second Deny: the system will not ask again.
      h.kit.calendar.afterRequest = DevicePermission.denied;
      await tester.tap(find.byKey(const ValueKey('today-brief-connect')));
      await settle(tester);
      expect(find.textContaining('Calendar access is blocked'), findsOneWidget);
      expect(
        find.textContaining('Open settings, allow Calendar'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('today-brief-connect')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('today-brief-open-settings')));
      await settle(tester);
      expect(h.kit.calendar.settingsOpened, 1);
    });

    todayTest('blocked, then allowed in system settings: coming back '
        'recovers on its own', (tester) async {
      final h = await pumpToday(tester);
      h.kit.calendar.items = [
        calEvent('e1', title: 'Design sync', start: at(9, 30)),
      ];
      h.kit.calendar.afterRequest = DevicePermission.denied;
      await tester.tap(find.byKey(const ValueKey('today-brief-connect')));
      await settle(tester);
      expect(find.textContaining('Calendar access is blocked'), findsOneWidget);

      // Back from settings, still off: the fix stays.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(find.textContaining('Calendar access is blocked'), findsOneWidget);

      h.kit.calendar.perm = DevicePermission.granted;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(find.textContaining('Calendar access is blocked'), findsNothing);
      expect(find.text('Up next'), findsOneWidget);
      expect(find.text('Design sync'), findsWidgets);
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

  group('brief: written by rules', () {
    todayTest('appears at once with no model: natural sentences, nothing '
        'written', (tester) async {
      final h = await pumpToday(
        tester,
        prefs: MemoryPrefsStore({
          'user_profile': jsonEncode({'name': 'Meera Menon'}),
        }),
        writer: FakeBriefWriter(model: BriefModelStatus.none),
        seed: _seedDay,
      );
      expect(
        _briefText(tester),
        'Meera, your first meeting is Design sync at 9:30 AM with Ravi, '
        'Sana and Dev. You have 2 meetings today, from 9:30 AM to 12:00 PM. '
        'Ravi Menon on WhatsApp is waiting for a reply. You also have 7 other '
        'notifications: 4 from Swiggy and 3 from HDFC.',
      );
      expect(h.writer.prompts, isEmpty);
      expect(find.text('Your day, at a glance'), findsNothing);
      expect(
        find.byKey(const ValueKey('today-brief-get-model')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('today-brief-rewrite')), findsNothing);
      expect(
        find.text('Made on this phone from your calendar and notifications'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('today-brief-get-model')));
      await settle(tester);
      expect(h.visited, contains('/settings/models'));
    });

    todayTest('the footer names only the sources that are connected', (
      tester,
    ) async {
      await pumpToday(
        tester,
        writer: FakeBriefWriter(model: BriefModelStatus.none),
        seed: (h) => h.seedCalendar(),
      );
      expect(
        find.text('Made on this phone from your calendar'),
        findsOneWidget,
      );
    });

    todayTest('with a model ready it still writes nothing on its own', (
      tester,
    ) async {
      final h = await pumpToday(tester, seed: _seedDay);
      expect(h.writer.prompts, isEmpty);
      expect(find.byKey(const ValueKey('today-brief-rewrite')), findsOneWidget);
      expect(
        find.textContaining('Your first meeting is Design sync'),
        findsOne,
      );
    });

    todayTest('tapping a cited phrase opens ITS source, not another', (
      tester,
    ) async {
      await pumpToday(tester, seed: _seedDay);
      await _tapCited(tester, 'Design sync at 9:30 AM');
      expect(find.byKey(const ValueKey('event-sheet-title')), findsOneWidget);
      expect(find.text('Design sync'), findsWidgets);
      Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
      await settle(tester);

      await _tapCited(tester, 'Ravi Menon on WhatsApp');
      expect(find.byKey(const ValueKey('event-sheet-title')), findsNothing);
      expect(find.textContaining('Wants your OK'), findsWidgets);
    });

    todayTest('"How this was written" lists the numbered facts, tappable', (
      tester,
    ) async {
      await pumpToday(tester, seed: _seedDay);
      expect(find.byKey(const ValueKey('today-brief-facts')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('today-brief-how')));
      await settle(tester);
      expect(find.byKey(const ValueKey('today-brief-facts')), findsOneWidget);
      expect(find.byKey(const ValueKey('fact-1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('fact-1')));
      await settle(tester);
      expect(find.byKey(const ValueKey('event-sheet-title')), findsOneWidget);
    });

    todayTest('Mark all read removes the notification facts', (tester) async {
      await pumpToday(tester, seed: _seedDay);
      expect(_briefText(tester), contains('Ravi Menon on WhatsApp'));
      expect(_briefText(tester), contains('7 other notifications'));
      await tester.ensureVisible(
        find.byKey(const ValueKey('digest-mark-read')),
      );
      await tester.tap(find.byKey(const ValueKey('digest-mark-read')));
      await settle(tester);
      expect(_briefText(tester), isNot(contains('Ravi Menon')));
      expect(_briefText(tester), isNot(contains('waiting')));
      expect(_briefText(tester), isNot(contains('notifications')));
      expect(_briefText(tester), contains('Design sync'));
      await tester.tap(find.byKey(const ValueKey('today-brief-how')));
      await settle(tester);
      expect(find.textContaining('WhatsApp'), findsNothing);
    });

    todayTest('an empty calendar says so, with tomorrow\'s first event', (
      tester,
    ) async {
      await pumpToday(
        tester,
        seed: (h) async {
          h.kit.calendar.items = [
            calEvent(
              'e9',
              title: 'Standup',
              start: DateTime(2026, 11, 3, 9),
              attendees: const [Person(name: 'Sana', email: 'sana@x.test')],
            ),
          ];
          await h.kit.hub.calendar.connect();
          await h.kit.hub.sync.refresh();
        },
      );
      expect(
        _briefText(tester),
        'You have no meetings today. Tomorrow starts with Standup at 9:00 AM '
        'with Sana.',
      );
      await _tapCited(tester, 'Standup at 9:00 AM');
      expect(find.byKey(const ValueKey('event-sheet-title')), findsOneWidget);
    });

    todayTest('while a model downloads the card says so, with progress', (
      tester,
    ) async {
      final h = await pumpToday(
        tester,
        writer: FakeBriefWriter(model: BriefModelStatus.none),
        seed: _seedDay,
        download: const DownloadProgress(
          taskId: 't',
          repoId: 'org/model',
          fileName: 'm.gguf',
          state: DownloadState.running,
          downloadedBytes: 250,
          totalBytes: 1000,
        ),
      );
      expect(
        find.byKey(const ValueKey('today-brief-downloading')),
        findsOneWidget,
      );
      expect(find.text('Downloading your model · 25%'), findsOneWidget);
      expect(find.byKey(const ValueKey('today-brief-get-model')), findsNothing);
      expect(_briefText(tester), contains('Design sync at 9:30 AM'));
      expect(h.writer.prompts, isEmpty);
    });

    todayTest('a cached brief from before the check (v1) is never shown', (
      tester,
    ) async {
      final old = jsonEncode({
        'writtenAt': at(7, 30).millisecondsSinceEpoch,
        'raw': 'Your first meeting is Standup at 9:00 [1].',
        'facts': [
          {
            'n': 1,
            'kind': 'event',
            'text': 'Design sync at 9:30',
            'ref': 'event:1',
          },
        ],
      });
      await pumpToday(
        tester,
        prefs: MemoryPrefsStore({'today_brief_v1': old}),
        seed: _seedDay,
      );
      expect(find.textContaining('Standup'), findsNothing);
      expect(_briefText(tester), contains('Design sync at 9:30 AM'));
    });

    todayTest('disconnecting a source forgets a rewrite made from it', (
      tester,
    ) async {
      final h = await pumpToday(
        tester,
        prefs: MemoryPrefsStore({'today_brief_v1': _freshCache()}),
      );
      // The calendar was never connected here, so the cached rewrite (which
      // quotes an event) must be erased, not shown.
      expect(find.byKey(const ValueKey('today-brief-text')), findsNothing);
      expect(h.prefs.values['today_brief_v1'], '');
    });
  });

  group('brief: optional rewrite', () {
    const faithful =
        'Your day starts with Design sync at 9:30 AM, with Ravi, Sana and Dev '
        '[1]. You have 2 meetings today, until 12:00 PM [2]. Ravi Menon on '
        'WhatsApp is waiting for a reply [3].';
    // The exact kind of output a 0.5B model produced on device: the prompt's
    // old sample sentence, with valid markers.
    const fabricated =
        'Your first meeting is Standup at 9:00 [1]. Ana needs a reply about '
        'the invoice [2].';

    todayTest('a faithful rewrite is shown, cited, checked and cached', (
      tester,
    ) async {
      final h = await pumpToday(
        tester,
        writer: FakeBriefWriter(output: faithful),
        seed: _seedDay,
      );
      final before = _briefText(tester);
      await tester.tap(find.byKey(const ValueKey('today-brief-rewrite')));
      await settle(tester);

      expect(h.writer.prompts, hasLength(1));
      final prompt = h.writer.prompts.single;
      expect(prompt, contains('\n<sources>\n'));
      expect(prompt, contains('Design sync at 9:30 AM'));
      expect(prompt, isNot(contains('Standup')));
      expect(prompt, isNot(contains('Ana ')));

      final after = _briefText(tester);
      expect(after, isNot(before));
      expect(after, startsWith('Your day starts with Design sync'));
      expect(
        find.textContaining('Reworded on this phone at 7:42 AM'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('today-brief-kept')), findsNothing);
      await _tapCited(tester, 'Ravi Menon on WhatsApp');
      expect(find.byKey(const ValueKey('event-sheet-title')), findsNothing);

      final cached = jsonDecode(h.prefs.values['today_brief_v1']!) as Map;
      expect(cached['v'], 2);
      expect((cached['facts'] as List), isNotEmpty);
      expect(
        cached['raw'],
        contains('Ravi Menon on WhatsApp is waiting for a reply [3]'),
      );
    });

    todayTest('a fabricated rewrite is rejected whole: the checked version '
        'stays and nothing is cached', (tester) async {
      final h = await pumpToday(
        tester,
        writer: FakeBriefWriter(output: fabricated),
        seed: _seedDay,
      );
      final before = _briefText(tester);
      await tester.tap(find.byKey(const ValueKey('today-brief-rewrite')));
      await settle(tester);

      expect(h.writer.prompts, hasLength(1));
      expect(_briefText(tester), before);
      expect(find.textContaining('Standup'), findsNothing);
      expect(find.textContaining('Ana'), findsNothing);
      expect(find.text('Kept the checked version'), findsOneWidget);
      expect(h.prefs.values['today_brief_v1'] ?? '', '');
      // The button is back for another try.
      expect(find.byKey(const ValueKey('today-brief-rewrite')), findsOneWidget);
    });

    todayTest('a rewrite with one invented sentence among good ones is '
        'rejected whole', (tester) async {
      final h = await pumpToday(
        tester,
        writer: FakeBriefWriter(
          output:
              'Your day starts with Design sync at 9:30 AM [1]. '
              'Priya joins you at 10:00 [1].',
        ),
        seed: _seedDay,
      );
      final before = _briefText(tester);
      await tester.tap(find.byKey(const ValueKey('today-brief-rewrite')));
      await settle(tester);
      expect(_briefText(tester), before);
      expect(find.text('Kept the checked version'), findsOneWidget);
      expect(h.prefs.values['today_brief_v1'] ?? '', '');
    });

    todayTest('a rejected second try drops the first rewrite too', (
      tester,
    ) async {
      final h = await pumpToday(
        tester,
        writer: FakeBriefWriter(output: faithful),
        seed: _seedDay,
      );
      await tester.tap(find.byKey(const ValueKey('today-brief-rewrite')));
      await settle(tester);
      expect(find.textContaining('Reworded on this phone'), findsOneWidget);

      h.writer.output = fabricated;
      await tester.tap(find.byKey(const ValueKey('today-brief-regenerate')));
      await settle(tester);
      expect(find.textContaining('Standup'), findsNothing);
      expect(find.textContaining('Reworded on this phone'), findsNothing);
      expect(_briefText(tester), startsWith('Your first meeting is Design'));
      expect(find.text('Kept the checked version'), findsOneWidget);
      expect(h.prefs.values['today_brief_v1'], '');
    });

    todayTest('a crashed model leaves the checked brief and shows the fix', (
      tester,
    ) async {
      final h = await pumpToday(
        tester,
        writer: FakeBriefWriter()..failWith = StateError('model crashed'),
        seed: _seedDay,
      );
      final before = _briefText(tester);
      await tester.tap(find.byKey(const ValueKey('today-brief-rewrite')));
      await settle(tester);
      expect(_briefText(tester), before);
      expect(find.byKey(const ValueKey('today-brief-error')), findsOneWidget);
      expect(h.prefs.values['today_brief_v1'] ?? '', '');
    });

    todayTest('a busy phone says so and keeps the checked brief', (
      tester,
    ) async {
      await pumpToday(
        tester,
        writer: FakeBriefWriter()
          ..failWith = const BriefUnavailable(
            'Your phone is busy with another task. Pull down to try again.',
          ),
        seed: _seedDay,
      );
      await tester.tap(find.byKey(const ValueKey('today-brief-rewrite')));
      await settle(tester);
      expect(find.byKey(const ValueKey('today-brief-error')), findsOneWidget);
      expect(_briefText(tester), contains('Your first meeting is Design sync'));
    });

    todayTest('an idle model is loaded on the tap, then used', (tester) async {
      final h = await pumpToday(
        tester,
        writer: FakeBriefWriter(model: BriefModelStatus.idle, output: faithful),
        seed: _seedDay,
        health: const DeviceHealth(batteryPercent: 3),
      );
      expect(h.writer.prepares, 0);
      await tester.tap(find.byKey(const ValueKey('today-brief-rewrite')));
      await settle(tester);
      expect(h.writer.prepares, 1);
      expect(find.textContaining('Reworded on this phone'), findsOneWidget);
    });

    todayTest('a fresh cached rewrite is shown without writing again', (
      tester,
    ) async {
      final first = await pumpToday(
        tester,
        writer: FakeBriefWriter(output: faithful),
        seed: _seedDay,
      );
      await tester.tap(find.byKey(const ValueKey('today-brief-rewrite')));
      await settle(tester);
      final cache = first.prefs.values['today_brief_v1']!;
      final h = await pumpToday(
        tester,
        prefs: MemoryPrefsStore({'today_brief_v1': cache}),
        seed: _seedDay,
      );
      expect(h.writer.prompts, isEmpty);
      expect(_briefText(tester), startsWith('Your day starts with Design'));
    });

    todayTest('a cached rewrite about other facts is dropped, never shown', (
      tester,
    ) async {
      final falseBrief = jsonEncode(
        WrittenBrief(
          writtenAt: at(7, 40),
          raw: 'You have no meetings today [1].',
          facts: const [
            BriefFact(
              n: 1,
              kind: FactKind.event,
              text: 'No meetings on the calendar today.',
              ref: 'event:0',
            ),
          ],
        ).toJson(),
      );
      final h = await pumpToday(
        tester,
        prefs: MemoryPrefsStore({'today_brief_v1': falseBrief}),
        seed: _seedDay,
      );
      expect(find.textContaining('no meetings'), findsNothing);
      expect(_briefText(tester), contains('Design sync'));
      expect(h.writer.prompts, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      expect(h.prefs.values['today_brief_v1'], '');
    });

    todayTest('Show original goes back and clears the cache', (tester) async {
      final h = await pumpToday(
        tester,
        writer: FakeBriefWriter(output: faithful),
        seed: _seedDay,
      );
      await tester.tap(find.byKey(const ValueKey('today-brief-rewrite')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('today-brief-original')));
      await settle(tester);
      expect(find.textContaining('Reworded on this phone'), findsNothing);
      expect(_briefText(tester), startsWith('Your first meeting is Design'));
      expect(h.prefs.values['today_brief_v1'], '');
    });

    todayTest('pull to refresh syncs but never starts the model', (
      tester,
    ) async {
      final h = await pumpToday(tester, seed: _seedDay);
      unawaited(
        tester
            .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
            .show(),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(h.writer.prompts, isEmpty);
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
      expect(
        tester
            .widget<AttendeeLine>(find.byKey(const ValueKey('up-next-people')))
            .names,
        ['Ravi', 'Sana', 'Dev'],
      );
      expect(
        find.textContaining('Budget review', findRichText: true),
        findsWidgets,
      );
      expect(find.textContaining('Room 4B', findRichText: true), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('up-next-prep')));
      await settle(tester);
      final uri = Uri.parse(h.visited.single);
      expect(uri.path, '/ask/new');
      expect(
        uri.queryParameters['q'],
        'Prep me for my 9:30 AM meeting: who is attending, what do I know '
        'about them, and any related notes.',
      );
      expect(uri.queryParameters['sources'], 'calendar,contacts,files');
      expect(int.tryParse(uri.queryParametersAll['focus']!.single), isNotNull);
      // The event's own (untrusted) title never rides in the prompt.
      expect(uri.queryParameters['q'], isNot(contains('Design sync')));
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
        tester
            .widget<AttendeeLine>(find.byKey(const ValueKey('up-next-people')))
            .names,
        ['Ravi Menon', 'Sana', 'Dev'],
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

    todayTest('the second row says Tomorrow when it is tomorrow', (
      tester,
    ) async {
      await pumpToday(
        tester,
        writer: FakeBriefWriter(model: BriefModelStatus.none),
        seed: (h) async {
          h.kit.calendar.items = [
            calEvent('e1', title: 'Design sync', start: at(9, 30)),
            calEvent('e3', title: 'Standup', start: DateTime(2026, 11, 3, 9)),
          ];
          await h.kit.hub.calendar.connect();
          await h.kit.hub.sync.refresh();
        },
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('up-next-second-time')))
            .data,
        'Tomorrow 9:00 AM',
      );
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
      // Read means read everywhere: Needs you goes too.
      expect(find.text('Needs you'), findsNothing);
    });

    todayTest('a long preview is cut by the row (one ellipsis), not by a '
        'pre-trimmed string', (tester) async {
      final long = notification(
        90,
        'in.news',
        'News',
        'News',
        'Markets   rallied\nafter the central bank held rates steady and '
            'signalled cuts later this year, analysts said on Monday morning.',
        at(7),
      );
      await pumpToday(
        tester,
        writer: FakeBriefWriter(model: BriefModelStatus.none),
        seed: (h) => h.seedNotifications([long]),
      );
      final row = tester.widget<RichText>(
        find
            .descendant(
              of: find.byKey(const ValueKey('today-digest')),
              matching: find.textContaining('Markets', findRichText: true),
            )
            .first,
      );
      final text = row.text.toPlainText();
      expect(text, contains('Monday morning.')); // whole text handed over
      expect(text, isNot(contains('…')));
      expect(text, isNot(contains('  Markets   ')));
      expect(row.overflow, TextOverflow.ellipsis);
      expect(row.maxLines, 1);
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
      expect(uri.path, '/ask/new');
      expect(uri.queryParameters['sources'], 'calendar');
      expect(uri.queryParameters['q'], startsWith('Plan my day'));
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
      expect(uri.path, '/ask/new');
      expect(uri.queryParameters['sources'], 'files');
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
      expect(find.text('Free until 9:30 AM'), findsOneWidget);
      final design = tester.getTopLeft(find.text('Design sync')).dy;
      final budget = tester.getTopLeft(find.text('Budget review')).dy;
      final now = tester.getTopLeft(find.text('Free until 9:30 AM')).dy;
      final ravi = tester.getTopLeft(find.textContaining('Wants your OK')).dy;
      expect(ravi, lessThan(now)); // 7:12 is before now (7:42)
      expect(now, lessThan(design));
      expect(design, lessThan(budget));
    });

    todayTest('overlapping meetings are marked on the rail', (tester) async {
      await pumpToday(
        tester,
        writer: FakeBriefWriter(model: BriefModelStatus.none),
        seed: (h) async {
          h.kit.calendar.items = [
            calEvent('e1', title: 'Design sync', start: at(9, 30)),
            calEvent('e2', title: 'Budget review', start: at(10)),
            calEvent('e3', title: 'Lunch', start: at(13)),
          ];
          await h.kit.hub.calendar.connect();
          await h.kit.hub.sync.refresh();
        },
      );
      await tester.tap(find.byKey(const ValueKey('today-see-day')));
      await settle(tester);
      expect(find.text('Overlaps Budget review'), findsOneWidget);
      expect(find.text('Overlaps Design sync'), findsOneWidget);
      expect(find.textContaining('Overlaps Lunch'), findsNothing);
      expect(
        find.textContaining('Overlaps', skipOffstage: false),
        findsNWidgets(2),
      );
    });

    todayTest('every row paints a rail segment, joined top to bottom', (
      tester,
    ) async {
      await pumpToday(
        tester,
        writer: FakeBriefWriter(model: BriefModelStatus.none),
        seed: _seedDay,
      );
      await tester.tap(find.byKey(const ValueKey('today-see-day')));
      await settle(tester);
      final rows = <int>[
        for (
          var i = 0;
          find.byKey(ValueKey('timeline-$i')).evaluate().isNotEmpty;
          i++
        )
          i,
      ];
      expect(rows.length, greaterThan(2));
      double? prevBottom;
      for (final i in rows) {
        final row = find.byKey(ValueKey('timeline-$i'));
        final rail = find.descendant(
          of: row,
          matching: find.byKey(const ValueKey('timeline-rail')),
        );
        expect(rail, findsOneWidget, reason: 'row $i has no rail');
        final r = tester.getRect(rail);
        final rowRect = tester.getRect(row);
        expect(r.width, 2);
        expect(r.height, greaterThan(0), reason: 'row $i rail is empty');
        if (i < rows.length - 1) {
          // Runs to the bottom edge of its row, so it meets the next row's.
          expect(r.bottom, closeTo(rowRect.bottom, 0.5));
        } else {
          // The last row stops at its dot, not the card's bottom.
          expect(r.bottom, lessThan(rowRect.bottom));
        }
        if (prevBottom != null) expect(r.top, closeTo(prevBottom, 0.5));
        prevBottom = r.bottom;
      }
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
