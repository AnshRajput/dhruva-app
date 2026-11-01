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
