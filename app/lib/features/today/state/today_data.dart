/// Today's data, derived from the Wave 2A connector providers (reused, not
/// duplicated): calendar status, today's events, the next two events, people
/// from the contacts connector, notification groups and the local "read"
/// flag. Everything is overridable in tests.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/ask_providers.dart' show askContactNamesProvider;
import '../../../core/di/connector_providers.dart';
import '../../../core/di/library_providers.dart';
import '../../../core/profile/user_profile.dart';
import '../../../core/settings/prefs_store.dart';
import '../../../data/connectors/connector.dart';
import '../../../data/connectors/connector_store.dart';
import '../../../data/connectors/needs_reply.dart';
import 'brief_compose.dart';
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

/// True once calendar access is off (the phone's settings took it back, or it
/// was never given): events the store still holds from before are stale, so
/// every Today surface reads none, derived from the live connector status
/// rather than from what happens to be stored. Unknown (the list is still
/// loading) and a failed read keep what is there.
final calendarOffProvider = Provider<bool>((ref) {
  final state = ref.watch(
    connectorListProvider.select(
      (v) => v.value
          ?.where((e) => e.connector.id == ConnectorIds.calendar)
          .firstOrNull
          ?.status
          .state,
    ),
  );
  return state == ConnectorState.permissionDenied ||
      state == ConnectorState.notConnected;
});

/// Events on the local calendar day of [todayClockProvider]; re-queried when
/// the date changes. None while calendar access is off.
final todayEventsProvider = StreamProvider<List<ConnectorItem>>((ref) {
  if (ref.watch(calendarOffProvider)) return Stream.value(const []);
  final store = ref.watch(connectorStoreProvider);
  return store.watchTodaysEvents(ref.watch(todayDayProvider));
});

/// The next two events from now (today or later), refreshed as time passes.
/// None while calendar access is off.
final upNextEventsProvider = StreamProvider<List<ConnectorItem>>((ref) {
  if (ref.watch(calendarOffProvider)) return Stream.value(const []);
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

/// Groups the digest card shows: last 24 h, not already in "Needs you". One
/// line per app. [groups] must already be unread
/// (`unreadNotificationGroupsProvider`).
List<NotificationGroup> digestGroups(
  List<NotificationGroup> groups,
  DateTime now,
) {
  final waiting = {for (final w in needsYou(groups, now)) w.group.package};
  final out = <NotificationGroup>[];
  for (final g in groups) {
    if (waiting.contains(g.package)) continue;
    final fresh = [
      for (final i in g.items)
        if (now.difference(i.sentAt ?? i.updatedAt) <= needsYouWindow) i,
    ];
    if (fresh.isEmpty) continue;
    out.add(
      NotificationGroup(package: g.package, appLabel: g.appLabel, items: fresh),
    );
  }
  return out;
}

/// The notification groups with what the user marked read removed: the one
/// view of notifications every Today surface (brief facts, Needs you, the
/// day summary) reads, so "Mark all read" means the same everywhere.
final unreadNotificationGroupsProvider = Provider<List<NotificationGroup>>((
  ref,
) {
  final groups = ref.watch(notificationGroupsProvider).value ?? const [];
  return unreadGroups(groups, ref.watch(notificationsReadAtProvider).value);
});

/// Open to-dos in the Library (0 while it loads or when the store is absent).
final openTodoCountProvider = Provider<int>((ref) {
  final todos = ref.watch(todosProvider).value ?? const [];
  return todos.where((t) => !t.done).length;
});

/// How many captured messages the Inbox lists under "Needs reply": the same
/// rule (`needsReply`) over the same items, minus system packages and what the
/// user marked read on Today.
int needsReplyCount(
  List<ConnectorItem> items,
  Set<String> knownContacts,
  DateTime? readAt,
) => needsReplyIds([
  for (final i in items)
    if (!systemPackages.contains(i.packageName) &&
        (readAt == null || i.when.isAfter(readAt)))
      i,
], knownContacts: knownContacts).length;

/// The one "needs a reply" number on Today: the subtitle and the brief read
/// this, so they can't disagree with each other or with the Inbox.
final inboxReplyCountProvider = Provider<int>(
  (ref) => needsReplyCount(
    ref.watch(inboxNotificationsProvider).value ?? const [],
    {
      for (final n
          in ref.watch(askContactNamesProvider).value ?? const <String>[])
        n.toLowerCase(),
    },
    ref.watch(notificationsReadAtProvider).value,
  ),
);

/// The rule-written brief (see `brief_compose.dart`): sentences and the facts
/// they cite. Empty until every input has answered, so a half-loaded day never
/// reads as a different day.
final dayBriefProvider = Provider<DayBrief>((ref) {
  final now = ref.watch(nowProvider);
  final calendar = ref.watch(calendarEntryProvider);
  final events = ref.watch(todayEventsProvider);
  final groups = ref.watch(notificationGroupsProvider);
  final readAt = ref.watch(notificationsReadAtProvider);
  bool pending(AsyncValue<Object?> v) => !v.hasValue && !v.hasError;
  if (!ref.watch(connectorsLoadedProvider) || pending(events)) {
    return DayBrief.empty;
  }
  if (pending(groups) || readAt.isLoading) return DayBrief.empty;
  return composeBrief(
    now: now,
    todaysEvents: events.value ?? const [],
    upcoming: ref.watch(upNextEventsProvider).value ?? const [],
    notificationGroups: ref.watch(unreadNotificationGroupsProvider),
    calendarConnected: calendar?.status.isConnected ?? false,
    calendarSynced: calendar?.status.lastSyncAt != null,
    contactNames: ref.watch(contactNamesProvider),
    openTodos: ref.watch(openTodoCountProvider),
    needsReplyCount: ref.watch(inboxReplyCountProvider),
  );
});

/// The facts behind the brief.
final briefFactsProvider = Provider<List<BriefFact>>(
  (ref) => ref.watch(dayBriefProvider).facts,
);

/// Today's greeting name from About me, or null.
final todayNameProvider = Provider<String?>((ref) {
  final p = ref.watch(userProfileProvider).value;
  final n = p?.name.trim() ?? '';
  return n.isEmpty ? null : n;
});

/// "3 meetings · 2 replies waiting".
final daySummaryProvider = Provider<String>((ref) {
  final events = ref.watch(todayEventsProvider).value ?? const [];
  return daySummary(
    meetings: events.where((e) => !isAllDay(e)).length,
    replies: ref.watch(inboxReplyCountProvider),
  );
});
