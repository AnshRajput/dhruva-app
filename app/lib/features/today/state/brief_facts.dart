/// The building blocks of Today's brief: numbered facts and the rules that read
/// the day (who is waiting on you, event times, attendee names). Rules, not a
/// model, decide what is worth saying (`brief_compose.dart` turns them into
/// sentences). The optional on-device rewrite only rewords those sentences and
/// is checked against these facts (`brief_grounding.dart`).
///
/// Facts carry text that came from other people (event titles, notification
/// text), so they are UNTRUSTED: they only ever reach a prompt through the
/// delimited sources block (`brief_prompt.dart`), and a fact can never trigger
/// an action, only open its source when the user taps.
library;

import 'dart:ui' show PlatformDispatcher;

import '../../../data/connectors/connector.dart';
import '../../../data/connectors/connector_store.dart';

enum FactKind { event, notification, todo }

/// One numbered fact. [ref] says what a tap opens: `event:<item id>`
/// (`event:0` is the day timeline), `notif:<package>` or `todos:`.
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

/// "9:45 PM" or "21:45", following the phone's 12/24 h setting (the same
/// setting the cards beside it read), in the phone's local time. [use24]
/// overrides the setting (tests).
String clock(DateTime d, {bool? use24}) {
  final l = d.toLocal();
  final m = l.minute.toString().padLeft(2, '0');
  if (use24 ?? PlatformDispatcher.instance.alwaysUse24HourFormat) {
    return '${l.hour.toString().padLeft(2, '0')}:$m';
  }
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  return '$h:$m ${l.hour < 12 ? 'AM' : 'PM'}';
}

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

/// [groups] without anything the user already marked read ("Mark all read"
/// on the digest): notifications at or before [readAt] are gone, apps left
/// with nothing are dropped. A read notification is neither a fact nor a
/// reply someone is waiting for.
List<NotificationGroup> unreadGroups(
  List<NotificationGroup> groups,
  DateTime? readAt,
) {
  if (readAt == null) return groups;
  final out = <NotificationGroup>[];
  for (final g in groups) {
    final fresh = [
      for (final i in g.items)
        if (_at(i).isAfter(readAt)) i,
    ];
    if (fresh.isEmpty) continue;
    out.add(
      NotificationGroup(package: g.package, appLabel: g.appLabel, items: fresh),
    );
  }
  return out;
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

/// True when [a] and [b] cite the same sources (events and apps). A brief
/// written from other sources describes a different day and must not be shown.
bool sameFactSources(List<BriefFact> a, List<BriefFact> b) {
  final x = {for (final f in a) f.ref};
  final y = {for (final f in b) f.ref};
  return x.length == y.length && x.containsAll(y);
}
