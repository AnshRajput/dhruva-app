/// Finds what an Ask question needs in the user's own data: per selected
/// source, the top search hits (SearchIndex) plus, for calendar questions,
/// the coming week's events read directly; packed into one numbered, escaped
/// `<sources>` block that fits the model's context budget.
///
/// The index queries run off the UI isolate (drift's background connection;
/// the BM25 fallback ranks inside `Isolate.run`), so this never blocks a
/// frame.
library;

import 'dart:math' as math;

import '../docs/bm25.dart';
import '../docs/grounding.dart' show excerptBudgetChars;
import 'ask_sources.dart';
import 'connector.dart';
import 'connector_store.dart';
import 'search_index.dart';
import 'sources_block.dart';

/// Never put more than this many characters of sources in a prompt, however
/// big the context: more text dilutes a small model's attention.
const maxAskSourceChars = 6000;

/// Hits taken per source before packing.
const hitsPerSource = 6;

/// Calendar questions read this many days of events directly.
const calendarLookaheadDays = 7;
const _calendarDirectLimit = 8;

/// Characters of context free for sources: the doc-chat helper's budget,
/// capped. [promptChars] is what is already committed (system prompt, history,
/// the question).
int askSourceBudgetChars({
  required int contextTokens,
  required int maxAnswerTokens,
  required int promptChars,
}) => math.min(
  maxAskSourceChars,
  excerptBudgetChars(
    contextTokens: contextTokens,
    maxAnswerTokens: maxAnswerTokens,
    promptChars: promptChars,
  ),
);

/// Interleaves lists best-first: all firsts, then all seconds, ... so one
/// source cannot crowd the others out of a small budget. Duplicates (same
/// item id) keep their earliest place.
List<ConnectorItem> interleaveItems(List<List<ConnectorItem>> lists) {
  final seen = <int>{};
  final out = <ConnectorItem>[];
  final longest = lists.fold<int>(0, (n, l) => math.max(n, l.length));
  for (var i = 0; i < longest; i++) {
    for (final l in lists) {
      if (i < l.length && seen.add(l[i].id)) out.add(l[i]);
    }
  }
  return out;
}

final class AskRetrieval {
  /// What the model sees; [SourcesBlock.items] is what can be cited.
  final SourcesBlock block;

  /// The connector sources that were searched.
  final Set<AskSource> searched;
  const AskRetrieval(this.block, this.searched);
}

class AskRetriever {
  AskRetriever({required SearchIndex index, required ConnectorStore store})
    : _index = index,
      _store = store;

  final SearchIndex _index;
  final ConnectorStore _store;

  /// [sources] must already be limited to connected connector sources.
  /// [mentioned] are contact names found in the question: their events come
  /// first among the upcoming ones.
  Future<AskRetrieval> retrieve({
    required String question,
    required Set<AskSource> sources,
    required DateTime now,
    required int budgetChars,
    List<String> mentioned = const [],
    List<ConnectorItem> focus = const [],
    String? about,
  }) async {
    final searched = connectorSourcesOf(sources);
    if ((searched.isEmpty && focus.isEmpty) || budgetChars <= 0) {
      return AskRetrieval(buildSourcesBlock(const [], maxChars: 0), searched);
    }
    final lists = <List<ConnectorItem>>[];
    // Focus items (the file / notification the user is asking about) go
    // first, the parts that best match the question ahead of the rest, so a
    // long file keeps the section that answers it inside the budget.
    final focusFirst = _focusByRelevance(question, focus);

    if (searched.contains(AskSource.calendar)) {
      final start = DateTime(now.year, now.month, now.day);
      final upcoming = await _store.eventsBetween(
        start,
        start.add(const Duration(days: calendarLookaheadDays)),
        limit: _calendarDirectLimit,
      );
      lists.add(_withPeopleFirst(upcoming, mentioned));
    }
    for (final s in searched) {
      final id = s.connectorId!;
      final hits = await _index.search(
        // The person a thread is ABOUT is a retrieval term, not question text.
        about == null ? question : '$question $about',
        limit: hitsPerSource,
        sources: {id},
      );
      lists.add([for (final h in hits) h.item]);
    }
    // Calendar's direct list leads (it is first in [lists]); the rest take
    // turns by rank.
    final merged = [
      ...focusFirst,
      for (final i in interleaveItems(lists))
        if (!focusFirst.any((f) => f.id == i.id)) i,
    ];
    return AskRetrieval(
      buildSourcesBlock(
        merged,
        maxChars: budgetChars,
        // A focused file's sections may be long; give them room.
        maxItemChars: focus.isEmpty ? 1200 : 2500,
        about: about,
      ),
      searched,
    );
  }
}

List<ConnectorItem> _focusByRelevance(
  String question,
  List<ConnectorItem> focus,
) {
  if (focus.length < 2) return focus;
  final index = Bm25Index([for (final i in focus) i.body]);
  final order = <int>{
    for (final h in index.search(question)) h.index,
    for (var i = 0; i < focus.length; i++) i,
  };
  return [for (final i in order) focus[i]];
}

/// Connector sources the user has opted into (an account row exists), read
/// from the local database only. Pass [live] (the connector ids whose OS access
/// is on right now) to drop a source the user has since switched off in system
/// settings: its stored items must not be retrieved or cited (M1).
Future<Set<AskSource>> connectedAskSources(
  ConnectorStore store, {
  Set<String>? live,
}) async {
  final out = <AskSource>{};
  for (final s in AskSource.values) {
    final id = s.connectorId;
    if (id == null || (live != null && !live.contains(id))) continue;
    if (await store.account(id) != null) out.add(s);
  }
  return out;
}

List<ConnectorItem> _withPeopleFirst(
  List<ConnectorItem> events,
  List<String> names,
) {
  if (names.isEmpty) return events;
  final wanted = {for (final n in names) n.toLowerCase()};
  bool match(ConnectorItem e) => e.people.any((p) {
    final n = p.name?.toLowerCase();
    return n != null && wanted.contains(n);
  });
  return [...events.where(match), ...events.where((e) => !match(e))];
}
