/// Small pure text helpers for the Library: why a file cannot be searched, the
/// snippet shown under a search hit, the badge on a document row, how recent a
/// file is. Pure so tests pin them.
library;

/// Plain-words reason for a file's `unreadable` flag (`FolderFile.problem`).
String unreadableReason(String problem) => switch (problem) {
  'tooLarge' => 'Too large to read here',
  'tooLong' => 'Too long to read here',
  'empty' => 'The file is empty',
  'noText' => 'Scanned pages, no text to read',
  'encrypted' => 'Locked with a password',
  'unsupported' => 'This kind of file is not supported',
  'unsafe' => 'Could not be read safely',
  _ => 'Could not be read',
};

/// What the user can do about it, for the same `problem` codes.
String unreadableFix(String problem) => switch (problem) {
  'tooLarge' => 'Save a smaller copy or split it into parts.',
  'tooLong' => 'Split it into shorter files.',
  'empty' => 'Nothing to do, or add text to it.',
  'noText' => 'Export a text version, or save it as a searchable PDF.',
  'encrypted' => 'Remove the password and save a copy.',
  'unsupported' => 'Save it as PDF, Markdown or plain text.',
  'unsafe' => 'Save a fresh copy and try again.',
  _ => 'Save a fresh copy and try again.',
};

/// "PDF", "MD", "TXT" for the tile on a document row.
String fileBadge(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return 'FILE';
  final ext = name.substring(dot + 1).toUpperCase();
  return switch (ext) {
    'MARKDOWN' => 'MD',
    _ when ext.length > 4 => 'FILE',
    _ => ext,
  };
}

/// About [max] characters of [body] around the first word of [query] that it
/// contains (whole body start when none does), on one line, with ellipses
/// where text was cut.
String snippetFor(String body, String query, {int max = 140}) {
  final text = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return '';
  if (text.length <= max) return text;
  final lower = text.toLowerCase();
  var at = -1;
  for (final w in query.toLowerCase().split(RegExp(r'\s+'))) {
    if (w.length < 2) continue;
    final i = lower.indexOf(w);
    if (i >= 0) {
      at = i;
      break;
    }
  }
  var start = at < 0 ? 0 : at - max ~/ 3;
  if (start < 0) start = 0;
  if (start + max > text.length) start = text.length - max;
  // Do not start or end mid-word.
  if (start > 0) {
    final space = text.indexOf(' ', start);
    if (space >= 0 && space < start + 20) start = space + 1;
  }
  var end = start + max;
  if (end < text.length) {
    final space = text.lastIndexOf(' ', end);
    if (space > start + max ~/ 2) end = space;
  }
  final cut = text.substring(start, end).trim();
  return '${start > 0 ? '… ' : ''}$cut${end < text.length ? ' …' : ''}';
}

/// "today", "yesterday", "3 days ago", "2 weeks ago", else "3 Nov".
String changedAgo(DateTime at, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 14) return '$days days ago';
  if (days < 60) return '${days ~/ 7} weeks ago';
  const m = [
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
  return '${at.day} ${m[at.month - 1]}';
}
