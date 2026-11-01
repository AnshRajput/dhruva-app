/// One measured speed-test result plus the JSON file that keeps them.
///
/// Deliberately NOT in Drift (no schema change): a small
/// `speed_results.json` in the app support dir, keyed by `repoId::fileName`.
library;

import 'dart:convert';
import 'dart:io';

import 'speed_label.dart';

/// Stable key for a model: repo id + file name (a repo can ship many quants).
String speedKey(String repoId, String fileName) => '$repoId::$fileName';

final class SpeedResult {
  final double decodeTps;
  final double prefillTps;
  final int loadMs;
  final DateTime measuredAt;
  final String appVersion;

  const SpeedResult({
    required this.decodeTps,
    required this.prefillTps,
    required this.loadMs,
    required this.measuredAt,
    required this.appVersion,
  });

  SpeedLabel get label => speedLabelFor(decodeTps);

  Map<String, Object?> toJson() => {
    'decodeTps': decodeTps,
    'prefillTps': prefillTps,
    'loadMs': loadMs,
    'measuredAt': measuredAt.toUtc().toIso8601String(),
    'appVersion': appVersion,
  };

  /// Null when any field is missing/ill-typed or the numbers are not usable.
  static SpeedResult? tryParse(Object? json) {
    if (json is! Map) return null;
    final decode = json['decodeTps'];
    final prefill = json['prefillTps'];
    final load = json['loadMs'];
    final at = json['measuredAt'];
    final version = json['appVersion'];
    if (decode is! num || prefill is! num || load is! num) return null;
    if (at is! String || version is! String) return null;
    final when = DateTime.tryParse(at);
    if (when == null) return null;
    if (!decode.isFinite || decode < 0 || !prefill.isFinite || prefill < 0) {
      return null;
    }
    return SpeedResult(
      decodeTps: decode.toDouble(),
      prefillTps: prefill.toDouble(),
      loadMs: load.toInt(),
      measuredAt: when.toUtc(),
      appVersion: version,
    );
  }
}

final class SpeedResultStore {
  final File file;
  SpeedResultStore(this.file);

  // ponytail: one in-process writer chain; fine, only this app writes the file.
  Future<void> _writes = Future.value();

  /// A missing, unreadable or corrupt file yields an empty map (never throws);
  /// individual bad entries are dropped, good ones kept.
  Future<Map<String, SpeedResult>> load() async {
    try {
      if (!file.existsSync()) return {};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return {};
      final out = <String, SpeedResult>{};
      for (final e in decoded.entries) {
        final key = e.key;
        final result = SpeedResult.tryParse(e.value);
        if (key is String && result != null) out[key] = result;
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> put(String key, SpeedResult result) {
    return _writes = _writes.catchError((_) {}).then((_) async {
      final all = await load();
      all[key] = result;
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
        jsonEncode({for (final e in all.entries) e.key: e.value.toJson()}),
        flush: true,
      );
      await tmp.rename(file.path);
    });
  }
}
