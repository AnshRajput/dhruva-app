/// The model's rewrite of the brief and its cache. Only a rewrite that passed
/// the grounding check is ever stored (`checkRewrite`); it is cached WITH the
/// numbered facts it was checked against, so a tapped phrase still opens the
/// right source and "How this was written" shows exactly what it rests on.
///
/// The rule-written brief is never cached: it is recomputed from the data on
/// every build. A cached rewrite is shown only while it is fresh ([briefMaxAge]
/// and the same calendar day) AND the facts are unchanged. It is never written
/// in the background (see `BriefController`).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show listEquals;

import '../../../core/settings/prefs_store.dart';
import 'brief_facts.dart';
import 'brief_parser.dart';

const briefMaxAge = Duration(hours: 3);
const _cacheKey = briefCachePrefsKey;

/// Bumped when what a cached brief means changes. Version 1 held unchecked
/// model text, which small models filled with invented details: it is never
/// shown again.
const _cacheVersion = 2;

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
    'v': _cacheVersion,
    'writtenAt': writtenAt.millisecondsSinceEpoch,
    'raw': raw,
    'facts': [for (final f in facts) f.toJson()],
  };

  static WrittenBrief? fromJson(Object? j) {
    if (j is! Map || j['v'] != _cacheVersion) return null;
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

/// The rewrite to show now: only while it is fresh AND checked against exactly
/// today's [facts]. Anything else describes a different day.
WrittenBrief? shownRewrite(
  WrittenBrief? rewrite,
  List<BriefFact> facts,
  DateTime now,
) {
  if (rewrite == null || facts.isEmpty) return null;
  if (!listEquals(rewrite.facts, facts) || !isBriefFresh(rewrite, now)) {
    return null;
  }
  return rewrite;
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
