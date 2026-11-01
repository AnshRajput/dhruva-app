/// Plain-English date/greeting text for Today. No `intl` dependency: the app
/// is English-first and only needs a weekday/month name and a day-part.
library;

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "Monday 2 November".
String formatDayLine(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

/// "Good morning" / "Good afternoon" / "Good evening".
String greetingFor(DateTime d) {
  if (d.hour < 12) return 'Good morning';
  if (d.hour < 18) return 'Good afternoon';
  return 'Good evening';
}

/// "Good morning, Meera" (just the first name; no name, no comma).
String greetingWithName(DateTime d, String? name) {
  final first = (name ?? '').trim().split(RegExp(r'\s+')).first;
  return first.isEmpty ? greetingFor(d) : '${greetingFor(d)}, $first';
}

/// "in 1h 48m", "in 12m", "now", or a day word for a later day.
String relativeStart(DateTime start, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final startDay = DateTime(start.year, start.month, start.day);
  final days = startDay.difference(today).inDays;
  if (days == 1) return 'Tomorrow';
  if (days > 1) return _weekdays[start.weekday - 1];
  final mins = start.difference(now).inMinutes;
  if (mins <= 0) return 'now';
  if (mins < 60) return 'in ${mins}m';
  final h = mins ~/ 60;
  final m = mins % 60;
  return m == 0 ? 'in ${h}h' : 'in ${h}h ${m}m';
}

/// "45m", "1h", "1h 30m".
String durationLabel(Duration d) {
  final mins = d.inMinutes;
  if (mins < 60) return '${mins}m';
  final h = mins ~/ 60;
  final m = mins % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// "5 min ago", "2h ago", "yesterday" style age for the brief footer.
String ageLabel(DateTime then, DateTime now) {
  final mins = now.difference(then).inMinutes;
  if (mins < 1) return 'just now';
  if (mins < 60) return '$mins min ago';
  final h = mins ~/ 60;
  if (h < 24) return '${h}h ago';
  return 'yesterday';
}

/// "Tomorrow" or the weekday for an event on a later day than [now]; null for
/// today (and for the past, which Up next never shows).
String? dayLabel(DateTime start, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final days = DateTime(
    start.year,
    start.month,
    start.day,
  ).difference(today).inDays;
  if (days <= 0) return null;
  return days == 1 ? 'Tomorrow' : _weekdays[start.weekday - 1];
}
