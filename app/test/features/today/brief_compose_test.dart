// The rule-written brief: templates over the day's data, every sentence tied to
// the facts that back it, and the strict grounding check on a model's rewrite
// (including the exact fabricated outputs seen on device).

import 'package:dhruva/data/connectors/connector.dart';
import 'package:dhruva/data/connectors/connector_store.dart';
import 'package:dhruva/features/today/state/brief_compose.dart';
import 'package:dhruva/features/today/state/brief_facts.dart';
import 'package:dhruva/features/today/state/brief_grounding.dart';
import 'package:flutter_test/flutter_test.dart';

import 'today_fixtures.dart';

DayBrief compose({
  DateTime? now,
  List<ConnectorItem> events = const [],
  List<ConnectorItem> upcoming = const [],
  List<NotificationGroup> groups = const [],
  bool connected = true,
  bool synced = true,
  String? name,
  int todos = 0,
}) => composeBrief(
  now: now ?? fixtureNow,
  todaysEvents: events,
  upcoming: upcoming,
  notificationGroups: groups,
  calendarConnected: connected,
  calendarSynced: synced,
  contactNames: const {'sana@x.test': 'Sana Rao', 'dev@x.test': 'Dev Patel'},
  name: name,
  openTodos: todos,
  use24: false,
);

List<String> plain(DayBrief b) => [for (final s in b.sentences) s.plain];

void main() {
  final groups = [
    notifGroup([raviMessage]),
    notifGroup(swiggyPings.reversed.toList()),
    notifGroup(hdfcPings.reversed.toList()),
  ];

  group('composeBrief', () {
    test('a full day reads as natural sentences, in order', () {
      final b = compose(
        events: [budgetReview, designSync],
        groups: groups,
        name: 'Meera Shah',
      );
      expect(plain(b), [
        'Meera, your first meeting is Design sync at 9:30 AM with Ravi, '
            'Sana Rao and Dev Patel.',
        'You have 2 meetings today, from 9:30 AM to 12:00 PM.',
        'You are free from 10:15 AM to 11:00 AM.',
        'Ravi Menon on WhatsApp is waiting for a reply.',
        'You also have 7 other notifications: 4 from Swiggy and 3 from HDFC.',
      ]);
    });

    test('every tappable span cites the fact that says it', () {
      final b = compose(
        events: [budgetReview, designSync],
        groups: groups,
        name: 'Meera',
      );
      final refs = <String>[];
      for (final s in b.sentences) {
        for (final span in s.spans.where((x) => x.isCited)) {
          final fact = b.facts.firstWhere((f) => f.n == span.cites.single);
          refs.add(fact.ref);
        }
      }
      expect(refs, [
        'event:1', // first meeting -> Design sync, not Budget review
        'event:0', // day shape -> the timeline
        'event:1', // free stretch after Design sync
        'notif:com.whatsapp', // Ravi
        'notif:in.swiggy', // the rest, by app
      ]);
      expect(b.facts.map((f) => f.n), [
        for (var i = 1; i <= b.facts.length; i++) i,
      ]);
    });

    test('the rule-written sentences pass the strict grounding check', () {
      for (final b in [
        compose(
          events: [budgetReview, designSync],
          groups: groups,
          name: 'Meera',
          todos: 2,
        ),
        compose(events: const [], upcoming: [_tomorrow()], name: 'Meera'),
        compose(now: at(9, 45), events: [designSync]),
        compose(now: at(13), events: [designSync, budgetReview]),
      ]) {
        expect(b.sentences, isNotEmpty);
        for (final s in b.sentences) {
          final cites = {for (final sp in s.spans) ...sp.cites};
          final text = [
            for (final f in b.facts)
              if (cites.contains(f.n)) f.text,
          ].join('\n');
          expect(
            ungrounded(s.plain, text, names: {'Meera'}),
            isNull,
            reason: s.plain,
          );
        }
      }
    });

    test('an empty day says so, and names tomorrow\'s first event', () {
      final b = compose(
        events: const [],
        upcoming: [_tomorrow()],
        name: 'Meera',
      );
      expect(plain(b), [
        'Meera, you have no meetings today.',
        'Tomorrow starts with Standup at 9:00 AM with Sana Rao.',
      ]);
      expect(b.facts.last.ref, 'event:77');
    });

    test('a later day is named by weekday', () {
      final wed = event(
        78,
        'Offsite',
        DateTime(2026, 11, 4, 10),
        DateTime(2026, 11, 4, 11),
      );
      final b = compose(events: const [], upcoming: [wed]);
      expect(plain(b).last, 'Wednesday starts with Offsite at 10:00 AM.');
    });

    test('when every meeting is over', () {
      final b = compose(now: at(13), events: [designSync, budgetReview]);
      expect(plain(b), ["All 2 of today's meetings are over."]);
    });

    test('a meeting in progress reads "is on now until"', () {
      final b = compose(now: at(9, 45), events: [designSync], name: 'Meera');
      expect(
        plain(b).first,
        startsWith('Meera, Design sync is on now until 10:15 AM'),
      );
    });

    test('overlapping meetings are flagged', () {
      final clash = event(3, 'Standup', at(10), at(10, 30));
      final b = compose(events: [designSync, clash]);
      expect(
        plain(b),
        contains(
          'Heads up: Design sync and Standup overlap from 10:00 AM to '
          '10:15 AM.',
        ),
      );
    });

    test('late in the day, tomorrow is mentioned even with meetings left', () {
      final evening = event(5, 'Dinner', at(20), at(21));
      final b = compose(
        now: at(19),
        events: [evening],
        upcoming: [evening, _tomorrow()],
      );
      expect(plain(b).last, startsWith('Tomorrow starts with Standup'));
    });

    test('no name: no name', () {
      final b = compose(events: [designSync]);
      expect(plain(b).first, startsWith('Your first meeting is Design sync'));
    });

    test('an empty store before the first sync says nothing', () {
      expect(compose(synced: false).isEmpty, isTrue);
      expect(compose(connected: false).isEmpty, isTrue);
    });

    test('works from notifications alone when no calendar is connected', () {
      final b = compose(connected: false, groups: groups);
      expect(plain(b).first, 'Ravi Menon on WhatsApp is waiting for a reply.');
    });

    test('open to-dos add a line that opens the Library', () {
      final b = compose(events: [designSync], todos: 3);
      expect(plain(b).last, 'You also have 3 open to-dos in your Library.');
      expect(b.facts.last.kind, FactKind.todo);
      expect(b.facts.last.ref, 'todos:');
      expect(
        plain(compose(events: [designSync], todos: 1)).last,
        contains('1 open to-do in'),
      );
    });

    test('read notifications are neither facts nor people waiting', () {
      final b = compose(
        events: [designSync],
        groups: unreadGroups(groups, at(8)),
      );
      expect(b.facts.where((f) => f.kind == FactKind.notification), isEmpty);
      expect(plain(b).join(' '), isNot(contains('Ravi Menon')));
    });

    test('five sentences at most, ten facts at most', () {
      final many = [
        for (var i = 0; i < 8; i++)
          event(50 + i, 'Meeting $i', at(9 + i), at(9 + i, 30)),
        event(60, 'Diwali', at(0), at(23), allDay: true),
      ];
      final b = compose(events: many, groups: groups, todos: 2);
      expect(b.sentences.length, lessThanOrEqualTo(5));
      expect(b.facts.length, lessThanOrEqualTo(maxBriefFacts));
    });

    test('24-hour phones read 24-hour times', () {
      final b = composeBrief(
        now: fixtureNow,
        todaysEvents: [designSync],
        notificationGroups: const [],
        calendarConnected: true,
        use24: true,
      );
      expect(b.sentences.first.plain, contains('09:30'));
    });
  });

  group('checkRewrite (strict grounding)', () {
    // Facts of a small day.
    final day = compose(
      events: [designSync, budgetReview],
      groups: [
        notifGroup([raviMessage]),
      ],
    );
    final facts = day.facts;
    RewriteCheck check(String raw, {Set<String> names = const {}}) =>
        checkRewrite(raw, facts, names: names);

    test('rejects the exact sentences a 0.5B model copied from the prompt', () {
      final r = check(
        'Your first meeting is Standup at 9:00 [1]. Ana needs a reply about '
        'the invoice [2].',
      );
      expect(r.ok, isFalse);
      expect(r.sentences, isEmpty);
    });

    test('rejects each fabricated sentence on its own', () {
      expect(check('Your first meeting is Standup at 9:00 [1].').ok, isFalse);
      expect(check('Ana needs a reply about the invoice [2].').ok, isFalse);
      // Valid-looking marker, right time, wrong person.
      expect(check('Priya is joining Design sync at 9:30 [1].').ok, isFalse);
      // Right names, wrong time.
      expect(check('Design sync is at 10:30 with Ravi [1].').ok, isFalse);
    });

    test('rejects a marker that points at the wrong fact', () {
      // Ravi Menon is only in the WhatsApp fact, not the meeting.
      expect(check('Ravi Menon is waiting for you [1].').ok, isFalse);
    });

    test('rejects a citation to a fact that does not exist', () {
      final r = check('Design sync is at 9:30 AM [1]. Lunch is at noon [9].');
      expect(r.ok, isFalse);
    });

    test('rejects a rewrite with any sentence lacking a marker', () {
      expect(
        check('Design sync is at 9:30 AM [1]. It will be a busy day.').ok,
        isFalse,
      );
    });

    test('rejects invented counts, digits or number words', () {
      expect(check('You have 3 meetings today [2].').ok, isFalse);
      expect(check('You have three meetings today [2].').ok, isFalse);
      expect(check('You have 2 meetings today [2].').ok, isTrue);
      expect(check('You have two meetings today [2].').ok, isTrue);
    });

    test('accepts a faithful rewrite, in any clock style', () {
      const rewrite =
          'Your day starts with Design sync at 9:30 AM, joined by Ravi, '
          'Sana Rao and Dev Patel [1]. You have 2 meetings today, finishing at '
          '12:00 PM [2]. Ravi Menon on WhatsApp is waiting for a reply [4].';
      final r = check(rewrite);
      expect(r.ok, isTrue, reason: r.reason);
      expect(r.sentences, hasLength(3));
      expect(r.sentences.first.spans.any((s) => s.cites.contains(1)), isTrue);

      // The same times as 24-hour, "9:30am" and "9.30"-free variants.
      expect(
        check(
          'Design sync starts at 09:30 with Ravi, Sana Rao and Dev Patel [1].',
        ).ok,
        isTrue,
      );
      expect(check('Design sync starts at 9:30am [1].').ok, isTrue);
      expect(check('You have 2 meetings today until 12:00 PM [2].').ok, isTrue);
      expect(
        check('You have 2 meetings, the last ends at 12 PM [2].').ok,
        isTrue,
      );
      expect(check('You have 2 meetings today until 12:00 [2].').ok, isTrue);
    });

    test('markers first, per-line style is accepted when faithful', () {
      final r = check(
        '[1] Design sync at 9:30 AM with Ravi.\n[4] Ravi Menon on WhatsApp is '
        'waiting.',
      );
      expect(r.ok, isTrue, reason: r.reason);
    });

    test('the user\'s own name is allowed only when given', () {
      const raw = 'Meera, Design sync is at 9:30 AM [1].';
      expect(check(raw).ok, isFalse);
      expect(check(raw, names: {'Meera'}).ok, isTrue);
    });

    test('an intro line and <think> blocks are not claims', () {
      final r = check(
        '<think>Plan the answer.</think>\nHere is your brief:\n'
        'Design sync is at 9:30 AM [1].',
      );
      expect(r.ok, isTrue, reason: r.reason);
    });

    test('more than five sentences is not a brief', () {
      final lines = [
        for (final v in ['is at', 'starts at', 'begins at', 'opens at'])
          'Design sync $v 9:30 AM [1].',
        'Design sync kicks off at 9:30 AM [1].',
      ];
      expect(check(lines.join('\n')).ok, isTrue); // five is fine
      final six = [...lines, 'Design sync runs from 9:30 AM [1].'];
      expect(check(six.join('\n')).ok, isFalse);
    });

    test('garbage and empty output are rejected, never thrown on', () {
      expect(check('').ok, isFalse);
      expect(check('[[[[ ]]] 99 ((').ok, isFalse);
      expect(check('No numbers here at all.').ok, isFalse);
    });

    group('lowercase content words (the claim hides in the verb)', () {
      final standup = compose(
        events: [
          event(
            5,
            'Standup',
            at(13),
            at(13, 30),
            people: const [Person(name: 'Priya', email: 'priya@x.test')],
          ),
        ],
      );
      RewriteCheck standupCheck(String raw) =>
          checkRewrite(raw, standup.facts, draft: standup.sentences);

      test('rejects the exact fabrications seen on device', () {
        for (final raw in [
          'Standup at 1:00 PM with Priya is cancelled [1].',
          'Standup at 1:00 PM was moved to the boardroom [1].',
          'Standup at 1:00 PM with Priya, who is furious [1].',
          'Standup is at 1:00 PM [1]. You should skip it [1].',
        ]) {
          final r = standupCheck(raw);
          expect(r.ok, isFalse, reason: raw);
          expect(r.reason, contains('uses the word'), reason: raw);
        }
      });

      test('names the offending lowercase word', () {
        const f = 'Standup at 1:00 PM with Priya.';
        expect(
          ungrounded('Standup at 1:00 PM with Priya is cancelled', f),
          'the word "cancelled"',
        );
        expect(
          ungrounded('Standup was moved to the boardroom', f),
          'the word "moved"',
        );
        expect(ungrounded('Priya is furious', f), 'the word "furious"');
        expect(ungrounded('You should skip it', f), 'the word "should"');
      });

      test('still accepts faithful tone rewrites', () {
        for (final raw in [
          'Standup is at 1:00 PM with Priya [1].',
          'Your first meeting is Standup, starting at 1:00 PM with Priya [1].',
          'Priya joins you for Standup at 1:00 PM [1].',
          'Standup begins at 1:00 PM with Priya [1].',
          'Your day starts with Standup at 1:00 PM, joined by Priya [1].',
        ]) {
          final r = standupCheck(raw);
          expect(r.ok, isTrue, reason: '$raw ${r.reason}');
        }
      });

      test('words of the sentence being rewritten are not new claims', () {
        // "on" and "now" come from the draft; a word in neither is rejected.
        const f = 'Standup is on now until 1:30 PM.';
        expect(ungrounded('Standup is on now.', f), isNull);
        expect(ungrounded('Standup is delayed.', f), isNotNull);
        expect(
          ungrounded('Standup is delayed.', f, rewrites: 'Standup is delayed'),
          isNull,
        );
      });
    });

    test('12 and 24 hour clocks match each other, bare hours are strict', () {
      const f = 'Dinner at 9:45 PM with Sam.';
      expect(ungrounded('Dinner at 21:45.', f), isNull);
      expect(ungrounded('Dinner at 9:45 PM.', f), isNull);
      expect(ungrounded('Dinner at 9:45pm.', f), isNull);
      // AM is not PM.
      expect(ungrounded('Dinner at 9:45 AM.', f), isNotNull);
      expect(ungrounded('Dinner at 9:00 PM.', f), isNotNull);
      // A bare "9" is a number, and 9 is not in the facts.
      expect(ungrounded('Dinner at 9 with Sam.', f), isNotNull);
    });

    test('capitalised words: allowlist, sentence start, hyphens', () {
      const f = 'Q4-review at 3:00 PM (Room 4B).';
      expect(ungrounded('The Q4-review is on Monday at 3 PM.', f), isNull);
      expect(ungrounded('Tomorrow, the Q4-review is at 15:00.', f), isNull);
      expect(ungrounded('Your Offsite is at 3 PM.', f), isNotNull);
      // A sentence-initial common word is fine; a sentence-initial NAME is not.
      expect(ungrounded('Priya joins at 3 PM.', f), isNotNull);
      expect(ungrounded('Room 4B is open.', f), isNull);
    });
  });
}

ConnectorItem _tomorrow() => event(
  77,
  'Standup',
  DateTime(2026, 11, 3, 9),
  DateTime(2026, 11, 3, 9, 30),
  people: const [Person(name: 'Sana', email: 'sana@x.test')],
);
