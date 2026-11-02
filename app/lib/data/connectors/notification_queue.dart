/// Reads the append-only JSON-lines queue the Android `NotificationListener`
/// writes (title / text / app / time per notification). The listener and the
/// app never write the Drift database concurrently: the listener only appends
/// to this file, and Dart drains it on app open / sync.
///
/// Everything in the file is treated as untrusted input even though the
/// directory is app-private: lines are size-bounded, parsed defensively,
/// fields are type- and range-checked, corrupt lines are skipped (never fatal),
/// and total bytes read per drain are capped.
///
/// Files: `notifications.jsonl` (live), `notifications.jsonl.old` (the rotated,
/// size-capped predecessor) and `notifications.jsonl.processing.*` (a drain in
/// flight, or left by an interrupted one).
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Line schema version understood here.
const queueLineVersion = 1;

/// A line longer than this is skipped without parsing.
const maxQueueLineChars = 16 * 1024;

/// Most bytes read from the queue files in one drain; the rest is dropped.
const maxQueueBytesPerDrain = 2 * 1024 * 1024;

const maxNotificationTitleChars = 300;
const maxNotificationTextChars = 4 * 1024;
const maxNotificationAppChars = 100;

/// Earliest believable timestamp (2020-01-01 UTC).
final _minTime = DateTime.utc(2020).millisecondsSinceEpoch;

final _pkgPattern = RegExp(r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$');
final _controlChars = RegExp(r'[\u0000-\u0008\u000B-\u001F\u007F]');

final class QueuedNotification {
  final String pkg;
  final String app;
  final String title;
  final String text;
  final DateTime time;
  const QueuedNotification({
    required this.pkg,
    required this.app,
    required this.title,
    required this.text,
    required this.time,
  });

  /// Stable across re-reads of the same line (rotation can repeat one).
  String get dedupeId {
    final h = sha256.convert(
      utf8.encode('$pkg|${time.millisecondsSinceEpoch}|$title|$text'),
    );
    return h.toString().substring(0, 32);
  }
}

String _clean(String s, int max) {
  final c = s.replaceAll(_controlChars, '').trim();
  if (c.length <= max) return c;
  var end = max;
  final u = c.codeUnitAt(end - 1);
  if (u >= 0xD800 && u <= 0xDBFF) end--;
  return c.substring(0, end);
}

/// Parses one queue line, or null if it is corrupt / invalid / excluded.
/// [now] bounds the timestamp; [excluded] drops packages the user opted out.
QueuedNotification? parseQueueLine(
  String line, {
  required DateTime now,
  Set<String> excluded = const {},
}) {
  if (line.isEmpty || line.length > maxQueueLineChars) return null;
  final Object? raw;
  try {
    raw = jsonDecode(line);
  } on FormatException {
    return null;
  }
  if (raw is! Map) return null;
  if (raw['v'] != queueLineVersion) return null;
  final pkg = raw['pkg'];
  final app = raw['app'];
  final title = raw['title'];
  final text = raw['text'];
  final t = raw['t'];
  if (pkg is! String || pkg.length > 255 || !_pkgPattern.hasMatch(pkg)) {
    return null;
  }
  if (excluded.contains(pkg)) return null;
  if (app is! String? || title is! String? || text is! String?) return null;
  if (t is! int) return null;
  if (t < _minTime ||
      t > now.add(const Duration(days: 1)).millisecondsSinceEpoch) {
    return null;
  }
  final cTitle = _clean(title ?? '', maxNotificationTitleChars);
  final cText = _clean(text ?? '', maxNotificationTextChars);
  if (cTitle.isEmpty && cText.isEmpty) return null;
  final cApp = _clean(app ?? '', maxNotificationAppChars);
  return QueuedNotification(
    pkg: pkg,
    app: cApp.isEmpty ? pkg : cApp,
    title: cTitle,
    text: cText,
    time: DateTime.fromMillisecondsSinceEpoch(t, isUtc: true),
  );
}

/// What one drain found.
final class QueueBatch {
  final List<QueuedNotification> notifications;

  /// Lines that were corrupt, invalid or excluded.
  final int skipped;

  /// Deletes the drained files. Call only after the notifications are safely
  /// stored; if the app dies first, the next drain re-reads them (the dedupe
  /// id makes that harmless).
  final Future<void> Function() commit;

  const QueueBatch({
    required this.notifications,
    required this.skipped,
    required this.commit,
  });
}

class NotificationQueue {
  NotificationQueue(this.directory);

  final Directory directory;

  static const liveName = 'notifications.jsonl';
  static const oldName = 'notifications.jsonl.old';
  static const processingName = 'notifications.jsonl.processing';

  File _f(String name) => File(p.join(directory.path, name));

  /// Moves the live and rotated files aside (rename is atomic on one
  /// filesystem, so the listener's next append starts a fresh live file), then
  /// reads them. Nothing is deleted until [QueueBatch.commit].
  Future<QueueBatch> drain({
    required DateTime now,
    Set<String> excluded = const {},
  }) async {
    if (!directory.existsSync()) {
      return QueueBatch(
        notifications: const [],
        skipped: 0,
        commit: () async {},
      );
    }
    // Move the rotated + live files to `<processing>.<time>.<n>` (rotated one
    // first so order is oldest to newest). Files left by an interrupted drain
    // carry an earlier time, so they sort first.
    final stamp = DateTime.now().microsecondsSinceEpoch;
    var n = 0;
    for (final name in [oldName, liveName]) {
      final src = _f(name);
      if (!src.existsSync()) continue;
      try {
        src.renameSync(_f('$processingName.$stamp.${n++}').path);
      } on FileSystemException {
        // Raced with the listener; it will be picked up next time.
      }
    }
    final parts = [
      for (final e in directory.listSync())
        if (e is File && p.basename(e.path).startsWith('$processingName.')) e,
    ]..sort((a, b) => a.path.compareTo(b.path));

    final out = <QueuedNotification>[];
    var skipped = 0;
    var budget = maxQueueBytesPerDrain;
    for (final f in parts) {
      if (budget <= 0) break;
      final res = await _readLines(f, budget, now, excluded);
      out.addAll(res.items);
      skipped += res.skipped;
      budget -= res.bytes;
    }
    return QueueBatch(
      notifications: out,
      skipped: skipped,
      commit: () async {
        for (final f in parts) {
          try {
            if (f.existsSync()) f.deleteSync();
          } on FileSystemException {
            // Left for the next drain; dedupe ids make a re-read harmless.
          }
        }
      },
    );
  }

  Future<({List<QueuedNotification> items, int skipped, int bytes})> _readLines(
    File f,
    int budget,
    DateTime now,
    Set<String> excluded,
  ) async {
    final items = <QueuedNotification>[];
    var skipped = 0;
    var bytes = 0;
    try {
      final lines = f
          .openRead(0, budget)
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter());
      await for (final line in lines) {
        bytes += line.length + 1;
        final parsed = parseQueueLine(line, now: now, excluded: excluded);
        if (parsed == null) {
          if (line.trim().isNotEmpty) skipped++;
        } else {
          items.add(parsed);
        }
      }
    } on FileSystemException {
      skipped++;
    }
    // A file at or over the budget was cut mid-line: that last line is junk
    // and was already counted as skipped by the parser.
    return (items: items, skipped: skipped, bytes: bytes);
  }
}
