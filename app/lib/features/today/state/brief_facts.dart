/// The deterministic FACT LIST behind Today's brief. Rules, not a model, decide
/// what is worth saying (next events with attendees, conflicts, messages that
/// look like they need a reply, a notification digest). The on-device model
/// only phrases these numbered facts; every sentence it writes must cite one.
///
/// Facts carry text that came from other people (event titles, notification
/// text), so they are UNTRUSTED: they only ever reach a prompt through the
/// delimited sources block (`brief_prompt.dart`), and a fact can never trigger
/// an action, only open its source when the user taps.
library;

import '../../../data/connectors/connector.dart';
import '../../../data/connectors/connector_store.dart';
import 'event_info.dart';

enum FactKind { event, notification }

/// One numbered fact. [ref] says what a tap opens: `event:<item id>` or
/// `notif:<package>`.
final class BriefFact {
  const BriefFact({
    required this.n,
    required this.kind,
    required this.text,
    required this.ref,
  });

  final int n;
  final FactKind kind;
  final String text;
  final String ref;

  Map<String, Object> toJson() => {
    'n': n,
    'kind': kind.name,
    'text': text,
    'ref': ref,
  };

  static BriefFact? fromJson(Object? j) {
    if (j is! Map) return null;
    final n = j['n'];
    final kind = j['kind'];
    final text = j['text'];
    final ref = j['ref'];
    if (n is! int || kind is! String || text is! String || ref is! String) {
      return null;
    }
    final k = FactKind.values.where((e) => e.name == kind);
    if (k.isEmpty) return null;
    return BriefFact(n: n, kind: k.first, text: text, ref: ref);
  }

  @override
  bool operator ==(Object other) =>
      other is BriefFact &&
      other.n == n &&
      other.kind == kind &&
      other.text == text &&
      other.ref == ref;

  @override
  int get hashCode => Object.hash(n, kind, text, ref);
}

/// Messaging apps whose notifications are people writing to the user. A rule,
/// on purpose: no model decides what "needs a reply".
const messagingPackages = {
  'com.whatsapp',
  'com.whatsapp.w4b',
  'org.telegram.messenger',
  'org.thoughtcrime.securesms',
  'com.google.android.apps.messaging',
  'com.samsung.android.messaging',
  'com.android.mms',
  'com.google.android.gm',
  'com.microsoft.office.outlook',
  'com.Slack',
  'com.microsoft.teams',
  'com.discord',
  'com.facebook.orca',
};

/// Notifications older than this are not "waiting for you" any more.
const needsYouWindow = Duration(hours: 24);

/// A notification that looks like a person writing to the user: from a
/// messaging app, with a sender (a title that is not just the app's name) and
/// some text.
bool looksActionable(ConnectorItem item) {
  final pkg = item.flags['pkg'];
  if (pkg is! String || !messagingPackages.contains(pkg)) return false;
  final title = item.title.trim();
  final app = item.flags['app'];
  if (title.isEmpty || (app is String && app.trim() == title)) return false;
  return item.body.trim().isNotEmpty;
}

/// One "Needs you" row: the newest actionable notification of one app.
final class NeedsYouEntry {
  const NeedsYouEntry(this.group, this.item);
  final NotificationGroup group;
  final ConnectorItem item;
}

DateTime _at(ConnectorItem i) => i.sentAt ?? i.updatedAt;

/// Up to [limit] people-messages from the last [needsYouWindow], newest first,
/// one per app. Rules only, until Gmail exists.
List<NeedsYouEntry> needsYou(
  List<NotificationGroup> groups,
  DateTime now, {
  int limit = 3,
}) {
  final out = <NeedsYouEntry>[];
  for (final g in groups) {
    for (final i in g.items) {
      if (now.difference(_at(i)) > needsYouWindow) break; // newest first
      if (looksActionable(i)) {
        out.add(NeedsYouEntry(g, i));
        break;
      }
    }
  }
  out.sort((a, b) => _at(b.item).compareTo(_at(a.item)));
  return out.take(limit).toList();
}

DateTime? eventEnd(ConnectorItem e) {
  final end = e.flags['end'];
  return end is int ? DateTime.fromMillisecondsSinceEpoch(end) : null;
}

bool isAllDay(ConnectorItem e) => e.flags['allDay'] == true;

/// "9:30", 24 h. Used inside fact text; screens format with the locale.
String clock(DateTime d) => '${d.hour}:${d.minute.toString().padLeft(2, '0')}';

String oneLine(String s, int max) {
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length <= max ? t : '${t.substring(0, max - 1).trimRight()}…';
}

/// Display names of an event's attendees, resolved through [contactNames]
/// (lowercase email to contact name) when the contacts connector knows them.
List<String> attendeeNames(ConnectorItem e, Map<String, String> contactNames) {
  final names = <String>[];
  for (final p in e.people) {
    final email = p.email?.toLowerCase();
    final n = (email == null ? null : contactNames[email]) ?? p.name;
    final name = (n != null && n.trim().isNotEmpty)
        ? n.trim()
        : (p.email?.split('@').first ?? '');
    if (name.isNotEmpty && !names.contains(name)) names.add(name);
  }
  return names;
}

/// Gathers the facts for the brief, in the order worth saying them. Pure.
///
/// [calendarConnected] decides whether "no meetings" is a fact or silence.
List<BriefFact> gatherFacts({
  required DateTime now,
  required List<ConnectorItem> todaysEvents,
  required List<NotificationGroup> notificationGroups,
  required bool calendarConnected,
  Map<String, String> contactNames = const {},
  int maxFacts = 10,
}) {
  final texts = <(FactKind, String, String)>[];
  void add(FactKind k, String text, String ref) =>
      texts.add((k, oneLine(text, 220), ref));

  final timed = [
    for (final e in todaysEvents)
      if (!isAllDay(e) && e.startsAt != null) e,
  ]..sort((a, b) => a.startsAt!.compareTo(b.startsAt!));
  final remaining = [
    for (final e in timed)
      if ((eventEnd(e) ?? e.startsAt!).isAfter(now)) e,
  ];

  if (calendarConnected) {
    if (timed.isEmpty) {
      add(FactKind.event, 'No meetings on the calendar today.', 'event:0');
    } else if (remaining.isEmpty) {
      add(
        FactKind.event,
        "All ${timed.length} of today's meetings are over.",
        'event:${timed.last.id}',
      );
    }
  }

  for (final e in remaining.take(5)) {
    final start = e.startsAt!;
    final end = eventEnd(e);
    final who = attendeeNames(e, contactNames);
    final withText = who.isEmpty
        ? ''
        : ' with ${who.take(3).join(', ')}'
              '${who.length > 3 ? ' and ${who.length - 3} more' : ''}';
    // "Google Meet" or the room, never a raw meeting URL.
    final place = placeLabel(e);
    final where = place == null ? '' : ' (${oneLine(place, 40)})';
    final title = oneLine(e.title, 80);
    final ongoing = !start.isAfter(now);
    add(
      FactKind.event,
      ongoing
          ? '$title is on now${end == null ? '' : ' until ${clock(end)}'}'
                '$withText$where.'
          : '$title at ${clock(start)}$withText$where.',
      'event:${e.id}',
    );
  }

  for (var i = 0; i + 1 < remaining.length; i++) {
    final a = remaining[i];
    final b = remaining[i + 1];
    final aEnd = eventEnd(a);
    if (aEnd != null && aEnd.isAfter(b.startsAt!)) {
      final bEnd = eventEnd(b);
      final until = bEnd != null && bEnd.isBefore(aEnd) ? bEnd : aEnd;
      add(
        FactKind.event,
        '${oneLine(a.title, 60)} and ${oneLine(b.title, 60)} overlap from '
            '${clock(b.startsAt!)} to ${clock(until)}.',
        'event:${a.id}',
      );
    }
  }

  for (final e in todaysEvents.where(isAllDay).take(2)) {
    add(FactKind.event, 'All day: ${oneLine(e.title, 80)}.', 'event:${e.id}');
  }

  final waiting = needsYou(notificationGroups, now);
  for (final w in waiting) {
    add(
      FactKind.notification,
      '${oneLine(w.item.title, 40)} messaged on ${w.group.appLabel}: '
          '"${oneLine(w.item.body, 100)}"',
      'notif:${w.group.package}',
    );
  }

  final shown = {for (final w in waiting) w.group.package};
  final others = <NotificationGroup>[];
  var otherCount = 0;
  for (final g in notificationGroups) {
    if (shown.contains(g.package)) continue;
    final recent = g.items
        .where((i) => now.difference(_at(i)) <= needsYouWindow)
        .length;
    if (recent == 0) continue;
    others.add(g);
    otherCount += recent;
  }
  if (otherCount >= 3) {
    add(
      FactKind.notification,
      '$otherCount other notifications, mostly from '
          '${others.take(3).map((g) => g.appLabel).join(', ')}.',
      'notif:${others.first.package}',
    );
  }

  return [
    for (var i = 0; i < texts.length && i < maxFacts; i++)
      BriefFact(
        n: i + 1,
        kind: texts[i].$1,
        text: texts[i].$2,
        ref: texts[i].$3,
      ),
  ];
}

/// "3 meetings · 2 replies waiting" from real data; '' when there is nothing
/// to say.
String daySummary({required int meetings, required int replies}) {
  final parts = <String>[
    if (meetings > 0) '$meetings ${meetings == 1 ? 'meeting' : 'meetings'}',
    if (replies > 0) '$replies ${replies == 1 ? 'reply' : 'replies'} waiting',
  ];
  return parts.join(' · ');
}
