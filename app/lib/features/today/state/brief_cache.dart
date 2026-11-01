/// The written brief and its cache. The brief is cached WITH its numbered
/// facts, so a tapped phrase still opens the right source and "How this was
/// written" shows exactly what the model was given.
///
/// Freshness: a brief is regenerated on open when it is older than
/// [briefMaxAge] or from another calendar day. It is never generated in the
/// background (see `BriefController`).
library;

import 'dart:convert';

import '../../../core/settings/prefs_store.dart';
import 'brief_facts.dart';
import 'brief_parser.dart';

const briefMaxAge = Duration(hours: 3);
const _cacheKey = briefCachePrefsKey;

final class WrittenBrief {
  const WrittenBrief({
    required this.writtenAt,
    required this.raw,
    required this.facts,
  });

  final DateTime writtenAt;

  /// The model's text as written (markers included); parsed on demand so the
  /// UI always applies the same citation rules.
  final String raw;
  final List<BriefFact> facts;

  ParsedBrief parsed() =>
      parseBrief(raw, validIds: {for (final f in facts) f.n});

  BriefFact? fact(int n) {
    for (final f in facts) {
      if (f.n == n) return f;
    }
    return null;
  }

  Map<String, Object> toJson() => {
    'writtenAt': writtenAt.millisecondsSinceEpoch,
    'raw': raw,
    'facts': [for (final f in facts) f.toJson()],
  };

  static WrittenBrief? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = j['writtenAt'];
    final raw = j['raw'];
    final facts = j['facts'];
    if (at is! int || raw is! String || facts is! List) return null;
    return WrittenBrief(
      writtenAt: DateTime.fromMillisecondsSinceEpoch(at),
      raw: raw,
      facts: [for (final f in facts) ?BriefFact.fromJson(f)],
    );
  }
}

/// True while [brief] can be shown without writing a new one.
bool isBriefFresh(
  WrittenBrief brief,
  DateTime now, {
  Duration maxAge = briefMaxAge,
}) {
  final age = now.difference(brief.writtenAt);
  if (age.isNegative || age >= maxAge) return false;
  final w = brief.writtenAt;
  return w.year == now.year && w.month == now.month && w.day == now.day;
}

/// A cached brief quotes calendar events and notifications. Once the user
/// disconnects a source, anything written from it must go too.
bool briefStillAllowed(
  WrittenBrief brief, {
  required bool calendarConnected,
  required bool notificationsConnected,
}) {
  for (final f in brief.facts) {
    if (f.kind == FactKind.event && !calendarConnected) return false;
    if (f.kind == FactKind.notification && !notificationsConnected) {
      return false;
    }
  }
  return true;
}

class BriefCacheStore {
  BriefCacheStore(this._prefs);
  final PrefsStore _prefs;

  Future<WrittenBrief?> read() async {
    try {
      final raw = await _prefs.read(_cacheKey);
      if (raw == null || raw.isEmpty) return null;
      return WrittenBrief.fromJson(jsonDecode(raw));
    } on Object {
      return null;
    }
  }

  Future<void> write(WrittenBrief brief) =>
      _prefs.write(_cacheKey, jsonEncode(brief.toJson()));

  Future<void> clear() => _prefs.write(_cacheKey, '');
}
