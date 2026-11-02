/// The one set of "when" labels: a row's timestamp (Inbox, privacy ledger) and
/// a conversation's age (chat). Pure, so every screen reads the same words.
library;

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

/// "7:30" today (spelled by [clock], so it follows the 12 / 24 hour setting),
/// "Yesterday", a short weekday within the last week, else "3 Nov".
String shortWhen(DateTime at, DateTime now, String Function(DateTime) clock) {
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(at.year, at.month, at.day)).inDays;
  if (days <= 0) return clock(at);
  if (days == 1) return 'Yesterday';
  if (days < 7) return _weekdays[at.weekday - 1];
  return '${at.day} ${_months[at.month - 1]}';
}

/// "just now", "5m ago", "2h ago", "3d ago".
String timeAgo(DateTime time, [DateTime? now]) {
  final diff = (now ?? DateTime.now()).difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
