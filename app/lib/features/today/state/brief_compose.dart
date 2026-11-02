/// Today's brief, written by rules: 3 to 5 plain sentences built from the day's
/// data with fixed templates. No model, so it appears instantly, is always
/// true to the data, and costs no battery.
///
/// Every sentence is built TOGETHER with the numbered facts that back it, so a
/// tappable span always opens the source it talks about (`BriefSpan.cites`
/// holds the fact numbers). Facts exist only for the sentences shown; the full
/// list sits under "How this was written".
///
/// Event titles, attendee names and notification text are UNTRUSTED text from
/// other people. Here they are only placed into display strings; nothing in
/// them is ever interpreted as an instruction.
library;

import '../../../data/connectors/connector.dart';
import '../../../data/connectors/connector_store.dart';
import 'brief_facts.dart';
import 'brief_parser.dart';
import 'day_text.dart';
import 'event_info.dart';

/// The deterministic brief: the shown [sentences] and the [facts] they cite.
final class DayBrief {
  const DayBrief(this.facts, this.sentences);
  final List<BriefFact> facts;
  final List<BriefSentence> sentences;

  static const empty = DayBrief([], []);

  bool get isEmpty => sentences.isEmpty;
}

/// Most facts a brief can hold (sentences x the few facts one may cite).
const maxBriefFacts = 10;

/// Free stretches shorter than this are not worth mentioning.
const _minGap = Duration(minutes: 45);

/// After this hour a day with meetings left still mentions tomorrow's first.
const _lateHour = 18;

typedef _Fact = (FactKind, String, String);

/// One possible sentence: the facts it rests on and how to spell it once those
/// facts have numbers.
final class _Candidate {
  const _Candidate(this.order, this.priority, this.facts, this.spans);
  final int order; // reading order
  final int priority; // lower wins when more than 5 compete
  final List<_Fact> facts;
  final List<BriefSpan> Function(List<int> n) spans;
}

String _people(List<String> names) {
  if (names.isEmpty) return '';
  if (names.length == 1) return names.first;
  if (names.length <= 3) {
    return '${names.sublist(0, names.length - 1).join(', ')} and '
        '${names.last}';
  }
  final rest = names.length - 3;
  return '${names.take(3).join(', ')} and $rest ${_plural(rest, 'other', 'others')}';
}

String _plural(int n, String one, String many) => n == 1 ? one : many;

String _lowerFirst(String s) =>
    s.isEmpty ? s : '${s[0].toLowerCase()}${s.substring(1)}';

/// Spans for "A, B and C" where each item cites its own fact.
List<BriefSpan> _joinCited(List<String> texts, List<int> n) {
  final out = <BriefSpan>[];
  for (var i = 0; i < texts.length; i++) {
    if (i > 0) out.add(BriefSpan(i == texts.length - 1 ? ' and ' : ', '));
    out.add(BriefSpan(texts[i], [n[i]]));
  }
  return out;
}

/// Writes the brief for the moment [now]. Pure.
///
/// * [todaysEvents] are today's calendar events; [upcoming] the next events
///   from now (to find tomorrow's first).
/// * [notificationGroups] must already be free of what the user marked read
///   (`unreadGroups`).
/// * "No meetings" is said only once the calendar is [calendarConnected] AND
///   has finished a sync ([calendarSynced]): right after connecting the store
///   is empty, and an empty store is not an empty day.
/// * [name] (About me) opens the first sentence; [openTodos] adds a line when
///   there are open to-dos in the Library.
DayBrief composeBrief({
  required DateTime now,
  required List<ConnectorItem> todaysEvents,
  List<ConnectorItem> upcoming = const [],
  required List<NotificationGroup> notificationGroups,
  required bool calendarConnected,
  bool calendarSynced = true,
  Map<String, String> contactNames = const {},
  String? name,
  int openTodos = 0,
  bool? use24,
}) {
  String t(DateTime d) => clock(d, use24: use24);
  final cands = <_Candidate>[];

  final timed = [
    for (final e in todaysEvents)
      if (!isAllDay(e) && e.startsAt != null) e,
  ]..sort((a, b) => a.startsAt!.compareTo(b.startsAt!));
  final remaining = [
    for (final e in timed)
      if ((eventEnd(e) ?? e.startsAt!).isAfter(now)) e,
  ];

  String withPeople(ConnectorItem e) {
    final who = attendeeNames(e, contactNames);
    return who.isEmpty ? '' : ' with ${_people(who)}';
  }

  // 1. The first (or next, or current) meeting, or why there is none.
  if (calendarConnected && timed.isEmpty) {
    if (calendarSynced) {
      cands.add(
        _Candidate(
          0,
          0,
          const [
            (FactKind.event, 'No meetings on the calendar today.', 'event:0'),
          ],
          (n) => [
            const BriefSpan('You have '),
            BriefSpan('no meetings today', [n[0]]),
            const BriefSpan('.'),
          ],
        ),
      );
    }
  } else if (calendarConnected && remaining.isEmpty) {
    final text = "All ${timed.length} of today's meetings are over";
    cands.add(
      _Candidate(
        0,
        0,
        [(FactKind.event, '$text.', 'event:${timed.last.id}')],
        (n) => [
          BriefSpan(text, [n[0]]),
          const BriefSpan('.'),
        ],
      ),
    );
  } else if (remaining.isNotEmpty) {
    final e = remaining.first;
    final start = e.startsAt!;
    final end = eventEnd(e);
    final title = oneLine(e.title, 80);
    final people = withPeople(e);
    final place = placeLabel(e);
    final where = place == null ? '' : ' (${oneLine(place, 40)})';
    final ongoing = !start.isAfter(now);
    final core = ongoing
        ? '$title is on now${end == null ? '' : ' until ${t(end)}'}$people'
        : '$title at ${t(start)}$people';
    final lead = ongoing
        ? ''
        : remaining.length == timed.length
        ? 'Your first meeting is '
        : 'Your next meeting is ';
    cands.add(
      _Candidate(
        0,
        0,
        [(FactKind.event, '$core$where.', 'event:${e.id}')],
        (n) => [
          if (lead.isNotEmpty) BriefSpan(lead),
          BriefSpan(core, [n[0]]),
          const BriefSpan('.'),
        ],
      ),
    );
  }

  // 2. The shape of the day: how many meetings, from when to when.
  if (remaining.length >= 2) {
    final last = remaining
        .map((e) => eventEnd(e) ?? e.startsAt!)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final all = remaining.length == timed.length;
    final core = all
        ? '${remaining.length} meetings today, from '
              '${t(remaining.first.startsAt!)} to ${t(last)}'
        : '${remaining.length} meetings left today, the last ending at '
              '${t(last)}';
    cands.add(
      _Candidate(
        1,
        3,
        [(FactKind.event, '$core.', 'event:0')],
        (n) => [
          const BriefSpan('You have '),
          BriefSpan(core, [n[0]]),
          const BriefSpan('.'),
        ],
      ),
    );
  }

  // 3. Meetings that overlap.
  for (var i = 0; i + 1 < remaining.length; i++) {
    final a = remaining[i];
    final b = remaining[i + 1];
    final aEnd = eventEnd(a);
    if (aEnd == null || !aEnd.isAfter(b.startsAt!)) continue;
    final bEnd = eventEnd(b);
    final until = bEnd != null && bEnd.isBefore(aEnd) ? bEnd : aEnd;
    final core =
        '${oneLine(a.title, 60)} and ${oneLine(b.title, 60)} overlap from '
        '${t(b.startsAt!)} to ${t(until)}';
    cands.add(
      _Candidate(
        2,
        1,
        [(FactKind.event, '$core.', 'event:${a.id}')],
        (n) => [
          const BriefSpan('Heads up: '),
          BriefSpan(core, [n[0]]),
          const BriefSpan('.'),
        ],
      ),
    );
    break; // the first clash is the one worth a sentence
  }

  // 4. The longest free stretch between meetings still to come.
  ConnectorItem? gapAfter;
  DateTime? gapFrom;
  DateTime? gapTo;
  var gapLen = Duration.zero;
  for (var i = 0; i + 1 < remaining.length; i++) {
    final aEnd = eventEnd(remaining[i]);
    final bStart = remaining[i + 1].startsAt!;
    if (aEnd == null || !bStart.isAfter(aEnd)) continue;
    final len = bStart.difference(aEnd);
    if (len >= _minGap && len > gapLen) {
      gapLen = len;
      gapAfter = remaining[i];
      gapFrom = aEnd;
      gapTo = bStart;
    }
  }
  if (gapAfter != null) {
    final core = 'from ${t(gapFrom!)} to ${t(gapTo!)}';
    final ref = 'event:${gapAfter.id}';
    cands.add(
      _Candidate(
        3,
        5,
        [(FactKind.event, 'Free $core.', ref)],
        (n) => [
          const BriefSpan('You are free '),
          BriefSpan(core, [n[0]]),
          const BriefSpan('.'),
        ],
      ),
    );
  }

  // 5. Tomorrow's first event, when today is empty, over, or late.
  final today = DateTime(now.year, now.month, now.day);
  final later = [
    for (final e in upcoming)
      if (!isAllDay(e) &&
          e.startsAt != null &&
          DateTime(
            e.startsAt!.year,
            e.startsAt!.month,
            e.startsAt!.day,
          ).isAfter(today))
        e,
  ]..sort((a, b) => a.startsAt!.compareTo(b.startsAt!));
  if (calendarConnected &&
      later.isNotEmpty &&
      (remaining.isEmpty || now.hour >= _lateHour)) {
    final e = later.first;
    final day = relativeStart(e.startsAt!, now); // Tomorrow / Monday
    final core = '${oneLine(e.title, 80)} at ${t(e.startsAt!)}${withPeople(e)}';
    cands.add(
      _Candidate(
        4,
        remaining.isEmpty ? 1 : 6,
        [(FactKind.event, '$day: $core.', 'event:${e.id}')],
        (n) => [
          BriefSpan('$day starts with '),
          BriefSpan(core, [n[0]]),
          const BriefSpan('.'),
        ],
      ),
    );
  }

  // 6. All-day events.
  final allDay = todaysEvents.where(isAllDay).take(2).toList();
  if (allDay.isNotEmpty) {
    final titles = [for (final e in allDay) oneLine(e.title, 60)];
    cands.add(
      _Candidate(
        5,
        6,
        [
          for (final (i, e) in allDay.indexed)
            (FactKind.event, 'All day: ${titles[i]}.', 'event:${e.id}'),
        ],
        (n) => [
          const BriefSpan('All day today: '),
          ..._joinCited(titles, n),
          const BriefSpan('.'),
        ],
      ),
    );
  }

  // 7. People waiting on a reply.
  final waiting = needsYou(notificationGroups, now);
  if (waiting.isNotEmpty) {
    final who = [
      for (final w in waiting)
        '${oneLine(w.item.title, 40)} on ${w.group.appLabel}',
    ];
    cands.add(
      _Candidate(
        6,
        2,
        [
          for (final w in waiting)
            (
              FactKind.notification,
              '${oneLine(w.item.title, 40)} messaged on '
                  '${w.group.appLabel}: "${oneLine(w.item.body, 100)}"',
              'notif:${w.group.package}',
            ),
        ],
        (n) => [
          ..._joinCited(who, n),
          BriefSpan(
            ' ${waiting.length == 1 ? 'is' : 'are'} waiting for a reply.',
          ),
        ],
      ),
    );
  }

  // 8. Everything else that buzzed, counted by app.
  final shown = {for (final w in waiting) w.group.package};
  final byApp = <(String, String, int)>[];
  var otherCount = 0;
  for (final g in notificationGroups) {
    if (shown.contains(g.package)) continue;
    final recent = g.items.where((i) {
      final at = i.sentAt ?? i.updatedAt;
      return now.difference(at) <= needsYouWindow;
    }).length;
    if (recent == 0) continue;
    byApp.add((g.package, g.appLabel, recent));
    otherCount += recent;
  }
  if (otherCount >= 3) {
    byApp.sort((a, b) => b.$3.compareTo(a.$3));
    final top = byApp.take(3).toList();
    final listed = top.fold<int>(0, (n, a) => n + a.$3);
    final parts = [for (final a in top) '${a.$3} from ${a.$2}'];
    final rest = otherCount - listed;
    // One app owns them all: "7 notifications from Shell", not a list of one.
    final core = byApp.length == 1
        ? '$otherCount notifications from ${top.first.$2}'
        : '$otherCount other notifications: ${_people(parts)}'
              '${rest > 0 ? ', and $rest more' : ''}';
    cands.add(
      _Candidate(
        7,
        4,
        [(FactKind.notification, '$core.', 'notif:${top.first.$1}')],
        (n) => [
          const BriefSpan('You also have '),
          BriefSpan(core, [n[0]]),
          const BriefSpan('.'),
        ],
      ),
    );
  }

  // 9. Open to-dos.
  if (openTodos > 0) {
    final core = '$openTodos open ${_plural(openTodos, 'to-do', 'to-dos')}';
    cands.add(
      _Candidate(
        8,
        7,
        [(FactKind.todo, '$core in your Library.', 'todos:')],
        (n) => [
          const BriefSpan('You also have '),
          BriefSpan(core, [n[0]]),
          const BriefSpan(' in your Library.'),
        ],
      ),
    );
  }

  // Keep the five that matter most, in reading order.
  final chosen =
      ([...cands]..sort((a, b) => a.priority - b.priority))
          .take(maxBriefSentences)
          .toList()
        ..sort((a, b) => a.order - b.order);

  final facts = <BriefFact>[];
  final sentences = <BriefSentence>[];
  for (final c in chosen) {
    if (facts.length + c.facts.length > maxBriefFacts) continue;
    final ids = <int>[];
    for (final (kind, text, ref) in c.facts) {
      final n = facts.length + 1;
      ids.add(n);
      facts.add(
        BriefFact(n: n, kind: kind, text: oneLine(text, 220), ref: ref),
      );
    }
    sentences.add(BriefSentence(c.spans(ids)));
  }

  final first = (name ?? '').trim().split(RegExp(r'\s+')).first;
  if (first.isNotEmpty && sentences.isNotEmpty) {
    final s = sentences.first.spans;
    sentences[0] = BriefSentence(
      s.first.isCited
          ? [BriefSpan('$first, '), ...s]
          : [BriefSpan('$first, ${_lowerFirst(s.first.text)}'), ...s.skip(1)],
    );
  }
  return DayBrief(facts, sentences);
}
