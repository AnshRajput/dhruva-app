/// Today's data, derived from the Wave 2A connector providers (reused, not
/// duplicated): calendar status, today's events, the next two events, people
/// from the contacts connector, notification groups and the local "read"
/// flag. Everything is overridable in tests.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/connector_providers.dart';
import '../../../core/profile/user_profile.dart';
import '../../../core/settings/prefs_store.dart';
import '../../../data/connectors/connector.dart';
import '../../../data/connectors/connector_store.dart';
import 'brief_facts.dart';

/// "Now" for Today. Tests override it.
final todayClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Ticks every 30 s so "in 1h 48m" and Up next move on while the app is open.
final minuteTickProvider = StreamProvider<DateTime>((ref) async* {
  final clock = ref.watch(todayClockProvider);
  yield clock();
  yield* Stream.periodic(const Duration(seconds: 30), (_) => clock());
});

/// "Now" as the screens see it: moves on with the ticker while Today is open.
final nowProvider = Provider<DateTime>((ref) {
  return ref.watch(minuteTickProvider).value ?? ref.watch(todayClockProvider)();
});

/// The local calendar day; changes only at midnight.
final todayDayProvider = Provider<DateTime>((ref) {
  final day = ref.watch(
    minuteTickProvider.select((v) {
      final t = v.value;
      return t == null ? null : DateTime(t.year, t.month, t.day);
    }),
  );
  if (day != null) return day;
  final now = ref.watch(todayClockProvider)();
  return DateTime(now.year, now.month, now.day);
});

/// The status entry of one connector, or null while the list loads / the
/// platform does not offer it.
ConnectorEntry? _entry(Ref ref, String id) {
  final list = ref.watch(connectorListProvider).value;
  if (list == null) return null;
  for (final e in list) {
    if (e.connector.id == id) return e;
  }
  return null;
}

final calendarEntryProvider = Provider<ConnectorEntry?>(
  (ref) => _entry(ref, ConnectorIds.calendar),
);

final contactsEntryProvider = Provider<ConnectorEntry?>(
  (ref) => _entry(ref, ConnectorIds.contacts),
);

final notificationsEntryProvider = Provider<ConnectorEntry?>(
  (ref) => _entry(ref, ConnectorIds.notifications),
);

/// True once the connector list has loaded (so "not connected" is real, not a
/// loading blip).
final connectorsLoadedProvider = Provider<bool>(
  (ref) => ref.watch(connectorListProvider).hasValue,
);

/// Events on the local calendar day of [todayClockProvider]; re-queried when
/// the date changes.
final todayEventsProvider = StreamProvider<List<ConnectorItem>>((ref) {
  final store = ref.watch(connectorStoreProvider);
  return store.watchTodaysEvents(ref.watch(todayDayProvider));
});

/// The next two events from now (today or later), refreshed as time passes.
final upNextEventsProvider = StreamProvider<List<ConnectorItem>>((ref) {
  final store = ref.watch(connectorStoreProvider);
  return store.watchNextEvents(ref.watch(nowProvider));
});

/// Lowercase email -> contact item, for names and avatars. Rebuilt when events
/// or a sync change (the contacts connector fills in after the calendar).
final contactsDirectoryProvider = FutureProvider<Map<String, ConnectorItem>>((
  ref,
) async {
  ref.watch(todayEventsProvider);
  ref.watch(upNextEventsProvider);
  ref.watch(connectorListProvider);
  final items = await ref
      .watch(connectorStoreProvider)
      .itemsOf(ConnectorIds.contacts, kind: ItemKind.contact);
  return {
    for (final c in items)
      for (final p in c.people)
        if (p.email != null) p.email!.toLowerCase(): c,
  };
});

/// Lowercase email -> contact name.
final contactNamesProvider = Provider<Map<String, String>>((ref) {
  final dir = ref.watch(contactsDirectoryProvider).value ?? const {};
  return {for (final e in dir.entries) e.key: e.value.title};
});

/// "Mark all read" for the digest: notifications at or before this moment are
/// hidden from the digest card. A local flag; nothing is sent anywhere.
class NotificationsReadAt extends AsyncNotifier<DateTime?> {
  static const key = 'notifications_read_at';

  @override
  Future<DateTime?> build() async {
    final store = await ref.watch(prefsStoreProvider.future);
    final ms = int.tryParse(await store.read(key) ?? '');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> markAllRead() async {
    final store = await ref.read(prefsStoreProvider.future);
    final now = ref.read(todayClockProvider)();
    state = AsyncData(now);
    await store.write(key, now.millisecondsSinceEpoch.toString());
  }
}

final notificationsReadAtProvider =
    AsyncNotifierProvider<NotificationsReadAt, DateTime?>(
      NotificationsReadAt.new,
    );

/// Groups the digest card shows: last 24 h, not already in "Needs you", not
/// marked read. One line per app.
List<NotificationGroup> digestGroups(
  List<NotificationGroup> groups,
  DateTime now, {
  DateTime? readAt,
}) {
  final waiting = {for (final w in needsYou(groups, now)) w.group.package};
  final out = <NotificationGroup>[];
  for (final g in groups) {
    if (waiting.contains(g.package)) continue;
    final fresh = [
      for (final i in g.items)
        if (now.difference(i.sentAt ?? i.updatedAt) <= needsYouWindow &&
            (readAt == null || (i.sentAt ?? i.updatedAt).isAfter(readAt)))
          i,
    ];
    if (fresh.isEmpty) continue;
    out.add(
      NotificationGroup(package: g.package, appLabel: g.appLabel, items: fresh),
    );
  }
  return out;
}

/// The fact list behind the brief (see `brief_facts.dart`).
final briefFactsProvider = Provider<List<BriefFact>>((ref) {
  final now = ref.watch(nowProvider);
  final calendar = ref.watch(calendarEntryProvider);
  return gatherFacts(
    now: now,
    todaysEvents: ref.watch(todayEventsProvider).value ?? const [],
    notificationGroups: ref.watch(notificationGroupsProvider).value ?? const [],
    calendarConnected: calendar?.status.isConnected ?? false,
    contactNames: ref.watch(contactNamesProvider),
  );
});

/// Today's greeting name from About me, or null.
final todayNameProvider = Provider<String?>((ref) {
  final p = ref.watch(userProfileProvider).value;
  final n = p?.name.trim() ?? '';
  return n.isEmpty ? null : n;
});

/// "3 meetings · 2 replies waiting".
final daySummaryProvider = Provider<String>((ref) {
  final now = ref.watch(nowProvider);
  final events = ref.watch(todayEventsProvider).value ?? const [];
  final groups = ref.watch(notificationGroupsProvider).value ?? const [];
  return daySummary(
    meetings: events.where((e) => !isAllDay(e)).length,
    replies: needsYou(groups, now, limit: 99).length,
  );
});
