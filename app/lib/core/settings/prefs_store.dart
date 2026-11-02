/// Tiny persisted key/value store for app preferences (appearance, "what
/// moved" sheet dismissed, ...). One JSON file in the app support dir, same
/// "no new dependency, no Drift migration" approach as the onboarding flag and
/// the battery guard switch, but one file for all of them instead of a
/// sentinel file per setting.
///
/// Values are strings; callers parse. A missing/corrupt file reads as empty.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract interface class PrefsStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

final class FilePrefsStore implements PrefsStore {
  FilePrefsStore(this.directory);

  final Directory directory;

  File get _file => File(p.join(directory.path, 'app_prefs_v1.json'));

  Map<String, String> _load() {
    final fromMain = _read(_file);
    if (fromMain != null) return fromMain;
    // A file left corrupt by an older (non-atomic) write, or a crash between
    // the temp write and the rename: fall back to the last complete temp.
    return _read(File('${_file.path}.tmp')) ?? {};
  }

  /// Null when the file is missing or not valid JSON.
  Map<String, String>? _read(File f) {
    try {
      if (!f.existsSync()) return null;
      final decoded = jsonDecode(f.readAsStringSync());
      if (decoded is! Map) return null;
      return {
        for (final e in decoded.entries)
          if (e.value is String) e.key.toString(): e.value as String,
      };
    } on Object {
      return null;
    }
  }

  @override
  Future<String?> read(String key) async => _load()[key];

  /// Writes go to a temp file that is then renamed over the real one, so a
  /// kill mid-write leaves the old file whole instead of truncated JSON (which
  /// reads as `{}` and silently resets every preference, including "hide in app
  /// switcher"). Rename is atomic on the same directory.
  @override
  Future<void> write(String key, String value) async {
    final all = _load()..[key] = value;
    final tmp = File('${_file.path}.tmp');
    tmp
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(all), flush: true);
    tmp.renameSync(_file.path);
  }
}

/// In-memory store for tests and as a safe fallback.
final class MemoryPrefsStore implements PrefsStore {
  MemoryPrefsStore([Map<String, String>? initial]) : values = {...?initial};

  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

/// Where Today's written brief is cached. Here (not in `features/today`) so the
/// connector wipe, which lives below features, can clear it by name.
const briefCachePrefsKey = 'today_brief_v1';

// No automatic retry: a failed directory lookup should reach callers as an
// error (they all fall back to defaults), not leave their futures pending.
final prefsStoreProvider = FutureProvider<PrefsStore>((ref) async {
  return FilePrefsStore(await getApplicationSupportDirectory());
}, retry: (_, _) => null);
