/// "See day": today's events and notification groups on one rail, in time
/// order, with a "now" marker. Pure, so the slotting is testable.
library;

import '../../../data/connectors/connector.dart';
import '../../../data/connectors/connector_store.dart';
import 'brief_facts.dart';

sealed class TimelineEntry {
  const TimelineEntry(this.at);

  /// Where the entry sits on the rail.
  final DateTime at;
}

final class NowEntry extends TimelineEntry {
  const NowEntry(super.at, this.caption);

  /// "Free until 9:30", "In Design sync until 10:15" or "Nothing more today".
  final String caption;
}

final class EventEntry extends TimelineEntry {
  const EventEntry(
    super.at,
    this.event, {
    required this.isPast,
    this.overlapsWith,
  });
  final ConnectorItem event;
  final bool isPast;

  /// Title of another meeting that runs at the same time, or null.
  final String? overlapsWith;
}

/// One app's notifications from today, slotted at its newest one.
final class NotificationEntry extends TimelineEntry {
  const NotificationEntry(
    super.at,
    this.group,
    this.items, {
    required this.actionable,
  });
  final NotificationGroup group;

  /// Today's items of that app, newest first.
  final List<ConnectorItem> items;

  /// The newest item looks like a person writing to the user.
  final bool actionable;
}

DateTime _at(ConnectorItem i) => i.sentAt ?? i.updatedAt;

/// True when [a] and [b] are both on at some moment (touching ends do not
/// count; an event with no end is a point and never overlaps).
bool _overlap(ConnectorItem a, ConnectorItem b) {
  final aEnd = eventEnd(a);
  final bEnd = eventEnd(b);
  if (aEnd == null || bEnd == null) return false;
  return a.startsAt!.isBefore(bEnd) && b.startsAt!.isBefore(aEnd);
}

List<TimelineEntry> buildTimeline({
  required DateTime now,
  required List<ConnectorItem> events,
  required List<NotificationGroup> groups,
}) {
  final dayStart = DateTime(now.year, now.month, now.day);
  final dayEnd = dayStart.add(const Duration(days: 1));

  final out = <TimelineEntry>[];
  final timed = [
    for (final e in events)
      if (e.startsAt != null && !isAllDay(e)) e,
  ]..sort((a, b) => a.startsAt!.compareTo(b.startsAt!));
  for (final e in timed) {
    final end = eventEnd(e) ?? e.startsAt!;
    final clash = timed.where((o) => o != e && _overlap(e, o)).firstOrNull;
    out.add(
      EventEntry(
        e.startsAt!,
        e,
        isPast: !end.isAfter(now),
        overlapsWith: clash == null ? null : oneLine(clash.title, 40),
      ),
    );
  }
  for (final g in groups) {
    final today = [
      for (final i in g.items)
        if (!_at(i).isBefore(dayStart) && _at(i).isBefore(dayEnd)) i,
    ];
    if (today.isEmpty) continue;
    out.add(
      NotificationEntry(
        _at(today.first),
        g,
        today,
        actionable: looksActionable(today.first),
      ),
    );
  }

  // Stable time order; events win a tie so a meeting never hides under a ping.
  out.sort((a, b) {
    final c = a.at.compareTo(b.at);
    if (c != 0) return c;
    return (a is EventEntry ? 0 : 1).compareTo(b is EventEntry ? 0 : 1);
  });

  String caption() {
    for (final e in timed) {
      final start = e.startsAt!;
      final end = eventEnd(e) ?? start;
      if (!start.isAfter(now) && end.isAfter(now)) {
        return 'In ${oneLine(e.title, 40)} until ${clock(end)}';
      }
    }
    for (final e in timed) {
      if (e.startsAt!.isAfter(now)) return 'Free until ${clock(e.startsAt!)}';
    }
    return 'Nothing more today';
  }

  final marker = NowEntry(now, caption());
  final at = out.indexWhere((e) => e.at.isAfter(now));
  if (at < 0) {
    out.add(marker);
  } else {
    out.insert(at, marker);
  }
  return out;
}

/// True when the day has nothing to show (the marker alone does not count).
bool timelineIsEmpty(List<TimelineEntry> entries) =>
    entries.every((e) => e is NowEntry);
