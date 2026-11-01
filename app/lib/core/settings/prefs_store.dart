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
    try {
      if (!_file.existsSync()) return {};
      final decoded = jsonDecode(_file.readAsStringSync());
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if (e.value is String) e.key.toString(): e.value as String,
      };
    } on Object {
      return {};
    }
  }

  @override
  Future<String?> read(String key) async => _load()[key];

  @override
  Future<void> write(String key, String value) async {
    final all = _load()..[key] = value;
    _file
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(all));
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

final prefsStoreProvider = FutureProvider<PrefsStore>((ref) async {
  return FilePrefsStore(await getApplicationSupportDirectory());
});
