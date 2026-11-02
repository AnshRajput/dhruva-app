/// Local-time wording shared by every prompt and chip that shows when
/// something happens. A model that is handed UTC ("2026-11-02T06:30:00Z")
/// answers in UTC; these always render the phone's local time, 24-hour.
library;

import 'connector.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "Mon 2 Nov".
String shortDate(DateTime d) {
  final l = d.toLocal();
  return '${_weekdays[l.weekday - 1]} ${l.day} ${_months[l.month - 1]}';
}

/// "9:30" (24-hour, local).
String shortTime(DateTime d) {
  final l = d.toLocal();
  return '${l.hour}:${l.minute.toString().padLeft(2, '0')}';
}

/// "Mon 2 Nov, 11:00–12:00", "Mon 2 Nov, 11:00" without an end, or
/// "Mon 2 Nov, all day". Local time.
String whenText(DateTime start, {DateTime? end, bool allDay = false}) {
  final day = shortDate(start);
  if (allDay) return '$day, all day';
  final range = end == null || !end.isAfter(start)
      ? shortTime(start)
      : '${shortTime(start)}–${shortTime(end)}';
  return '$day, $range';
}

/// [whenText] for a connector item (calendar events carry `end`/`allDay` in
/// their flags), or null when it has no moment.
String? itemWhenText(ConnectorItem item) {
  final when = item.startsAt ?? item.sentAt;
  if (when == null) return null;
  final endMs = item.flags['end'];
  return whenText(
    when,
    end: endMs is int ? DateTime.fromMillisecondsSinceEpoch(endMs) : null,
    allDay: item.flags['allDay'] == true,
  );
}
