/// Meeting prep built by RULES from what is on the phone: no model writes it,
/// so nothing in it can be made up. The event's time and place, who is in it
/// and what is known of each person (contact, other meetings with them), then
/// notes and files that mention the meeting or the people, and their recent
/// notifications. Every row points at the stored item it came from.
///
/// The text of notes, files and notifications is untrusted: it is only shown
/// as text here, never followed.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/connector_providers.dart';
import '../../../data/connectors/connector.dart';
import 'today_data.dart';

/// One attendee with what the phone knows about them.
final class PrepPerson {
  const PrepPerson({
    required this.name,
    this.email,
    this.photoBase64,
    this.inContacts = false,
    this.otherMeetings = const [],
  });
  final String name;
  final String? email;
  final String? photoBase64;

  /// True when a contact item matched (name and photo came from Contacts).
  final bool inContacts;

  /// Other events in the calendar that this person is also in, soonest first.
  final List<ConnectorItem> otherMeetings;
}

final class PrepData {
  const PrepData({
    required this.event,
    required this.people,
    required this.files,
    required this.notifications,
  });
  final ConnectorItem event;
  final List<PrepPerson> people;

  /// Notes and files that match the title or an attendee.
  final List<ConnectorItem> files;

  /// Recent notifications from, or mentioning, an attendee.
  final List<ConnectorItem> notifications;

  bool get hasRelated => files.isNotEmpty || notifications.isNotEmpty;
}

/// Attendees of [event] with their contact and the other [events] they share.
List<PrepPerson> prepPeople(
  ConnectorItem event,
  Map<String, ConnectorItem> contacts,
  List<ConnectorItem> events,
) {
  final out = <PrepPerson>[];
  final seen = <String>{};
  for (final p in event.people) {
    final email = p.email?.toLowerCase();
    final c = email == null ? null : contacts[email];
    final name = (c?.title.isNotEmpty ?? false)
        ? c!.title
        : (p.name?.trim().isNotEmpty ?? false)
        ? p.name!.trim()
        : (email?.split('@').first ?? '');
    if (name.isEmpty || !seen.add(name.toLowerCase())) continue;
    final photo = c?.flags['photo'];
    final others = [
      for (final e in events)
        if (e.id != event.id &&
            e.people.any(
              (q) => email != null
                  ? q.email?.toLowerCase() == email
                  : q.name == p.name,
            ))
          e,
    ];
    out.add(
      PrepPerson(
        name: name,
        email: p.email,
        photoBase64: photo is String ? photo : null,
        inContacts: c != null,
        otherMeetings: others.take(3).toList(),
      ),
    );
  }
  return out;
}

/// Notifications from, or mentioning, one of [names], newest first, at most
/// [limit]. A notification title is the sender, so a title that is a person's
/// full name or starts with their first name counts; so does a body that
/// contains the full name.
List<ConnectorItem> notificationsAbout(
  List<String> names,
  List<ConnectorItem> notifications, {
  int limit = 4,
}) {
  bool matches(ConnectorItem n) {
    final title = n.title.toLowerCase();
    final body = n.body.toLowerCase();
    for (final raw in names) {
      final name = raw.toLowerCase().trim();
      if (name.length < 3) continue;
      final first = name.split(' ').first;
      if (title.contains(name) ||
          body.contains(name) ||
          (first.length >= 3 && title.split(' ').first == first)) {
        return true;
      }
    }
    return false;
  }

  final picked =
      [
        for (final n in notifications)
          if (matches(n)) n,
      ]..sort(
        (a, b) => (b.sentAt ?? b.updatedAt).compareTo(a.sentAt ?? a.updatedAt),
      );
  return picked.take(limit).toList();
}

/// Search words for notes and files about this meeting: the title and the
/// attendees' names.
List<String> prepQueries(ConnectorItem event, List<PrepPerson> people) => [
  if (event.title.trim().isNotEmpty) event.title.trim(),
  for (final p in people.take(3)) p.name,
];

/// The prep for one event, or null when it is gone.
final prepProvider = FutureProvider.autoDispose.family<PrepData?, int>((
  ref,
  eventId,
) async {
  final store = ref.watch(connectorStoreProvider);
  final event = (await store.itemsByIds([eventId])).firstOrNull;
  if (event == null) return null;
  final contacts = await ref.watch(contactsDirectoryProvider.future);
  final now = ref.read(todayClockProvider)();
  final day = DateTime(now.year, now.month, now.day);
  final events = await store.eventsBetween(
    day.subtract(const Duration(days: 30)),
    day.add(const Duration(days: 30)),
    limit: 200,
  );
  final people = prepPeople(event, contacts, events);

  final index = await ref.watch(searchIndexProvider.future);
  final files = <ConnectorItem>[];
  final seen = <String>{};
  for (final q in prepQueries(event, people)) {
    for (final h in await index.search(
      q,
      limit: 4,
      sources: {ConnectorIds.folder},
    )) {
      final key = h.item.title.isNotEmpty ? h.item.title : '${h.item.id}';
      if (seen.add(key)) files.add(h.item);
    }
  }
  final cutoff = now.subtract(const Duration(days: 7));
  final recent = [
    for (final n in await store.itemsOf(ConnectorIds.notifications))
      if (!(n.sentAt ?? n.updatedAt).isBefore(cutoff)) n,
  ];
  return PrepData(
    event: event,
    people: people,
    files: files.take(4).toList(),
    notifications: notificationsAbout([for (final p in people) p.name], recent),
  );
});
