/// Turns a question + the attached documents' chunks into a grounded prompt:
/// picks the best-matching excerpts that fit the model's context budget
/// (`selectExcerpts`), formats them with page tags (`buildGroundedPrompt`) and
/// works out which pages the answer actually cited (`citedSources`).
/// Pure Dart; no I/O.
library;

import 'dart:convert';

import 'bm25.dart';

/// Conservative characters-per-token used to turn the model's token budget
/// into a character budget. Real English averages ~4; 3 leaves headroom for
/// numbers, code and non-Latin text.
const charsPerToken = 3;

/// Tokens reserved for the chat template's role markers and the grounding
/// instructions themselves.
const _templateOverheadTokens = 200;

/// Never put more than this many excerpts in one prompt, however big the
/// context is: more text dilutes a small model's attention.
const maxExcerpts = 8;

/// A chunk loaded from storage, with enough about its document to cite it.
final class StoredChunk {
  final int docId;
  final String docName;

  /// True for a real paginated document (PDF); false for TXT/MD, whose
  /// "pages" are synthetic parts (see `splitIntoSections`).
  final bool paged;
  final int index;
  final int page;
  final String text;

  const StoredChunk({
    required this.docId,
    required this.docName,
    required this.paged,
    required this.index,
    required this.page,
    required this.text,
  });
}

/// One citation shown in the "Sources" row of a grounded reply.
final class DocSource {
  final String docName;
  final int page;
  final bool paged;
  final String snippet;

  const DocSource({
    required this.docName,
    required this.page,
    required this.paged,
    required this.snippet,
  });

  /// "p.3" for a PDF, "part 3" for a plain-text file.
  String get label => paged ? 'p.$page' : 'part $page';

  Map<String, Object> toJson() => {
    'doc': docName,
    'page': page,
    'paged': paged,
    'snippet': snippet,
  };

  static DocSource? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final doc = json['doc'];
    final page = json['page'];
    final snippet = json['snippet'];
    if (doc is! String || page is! int || snippet is! String) return null;
    return DocSource(
      docName: doc,
      page: page,
      paged: json['paged'] != false,
      snippet: snippet,
    );
  }
}

/// Encodes [sources] for `Messages.sourcesJson`.
String encodeSources(List<DocSource> sources) =>
    jsonEncode([for (final s in sources) s.toJson()]);

/// Decodes `Messages.sourcesJson`; null/garbage yields an empty list.
List<DocSource> decodeSources(String? json) {
  if (json == null || json.isEmpty) return const [];
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    return [for (final item in decoded) ?DocSource.tryFromJson(item)];
  } on FormatException {
    return const [];
  }
}

/// How many characters of excerpts fit alongside everything else.
///
/// [contextTokens] is the model's `n_ctx`, [maxAnswerTokens] the room kept
/// for the reply, and [promptChars] the characters already committed (system
/// prompt + chat history + the question itself).
int excerptBudgetChars({
  required int contextTokens,
  required int maxAnswerTokens,
  required int promptChars,
}) {
  final usedTokens =
      maxAnswerTokens +
      _templateOverheadTokens +
      (promptChars / charsPerToken).ceil();
  final free = contextTokens - usedTokens;
  return free <= 0 ? 0 : free * charsPerToken;
}

/// Per-excerpt formatting cost (the `[p.N]` header and spacing).
const _excerptHeaderChars = 24;

/// Smallest slice worth sending when not even one whole chunk fits.
const _minTruncatedChars = 300;

/// Picks the excerpts for [question]: BM25-ranked chunks, packed greedily
/// into [budgetChars] (at most [maxExcerpts]), returned in document order so
/// the model reads them as the author wrote them.
///
/// A question with no usable keywords (or no match, e.g. "summarize this")
/// falls back to the start of the document. When even one whole chunk would
/// not fit, the best chunk is truncated rather than dropped.
List<StoredChunk> selectExcerpts({
  required List<StoredChunk> chunks,
  required Bm25Index index,
  required String question,
  required int budgetChars,
  int limit = maxExcerpts,
}) {
  if (chunks.isEmpty || budgetChars <= 0) return const [];
  assert(index.length == chunks.length);
  final ranked = index.search(question);
  final order = ranked.isNotEmpty
      ? [for (final s in ranked) s.index]
      : List<int>.generate(chunks.length, (i) => i);

  final picked = <int, StoredChunk>{};
  var remaining = budgetChars;
  for (final i in order) {
    if (picked.length >= limit) break;
    final chunk = chunks[i];
    final cost = chunk.text.length + _excerptHeaderChars;
    if (cost <= remaining) {
      picked[i] = chunk;
      remaining -= cost;
    } else if (picked.isEmpty &&
        remaining - _excerptHeaderChars >= _minTruncatedChars) {
      final room = remaining - _excerptHeaderChars;
      picked[i] = StoredChunk(
        docId: chunk.docId,
        docName: chunk.docName,
        paged: chunk.paged,
        index: chunk.index,
        page: chunk.page,
        text: '${chunk.text.substring(0, room).trimRight()}…',
      );
      remaining = 0;
    }
  }
  final keys = picked.keys.toList()..sort();
  return [for (final k in keys) picked[k]!];
}

/// The grounded user turn plus the citations it offers.
final class GroundedPrompt {
  final String prompt;
  final List<DocSource> sources;
  const GroundedPrompt(this.prompt, this.sources);
}

/// Builds the user turn that replaces the plain [question] when documents
/// are attached. Excerpts are tagged `[p.N]` (with the file name when more
/// than one document is attached) so the model can cite them.
GroundedPrompt buildGroundedPrompt({
  required String question,
  required List<StoredChunk> excerpts,
}) {
  final multiDoc = excerpts.map((e) => e.docId).toSet().length > 1;
  final b = StringBuffer()
    ..writeln(
      'Answer the question using only the document excerpts below. '
      'If the answer is not in the excerpts, say that the document does not '
      'say; do not guess or use outside knowledge. '
      'After each fact, cite its page like [p.3].',
    )
    ..writeln();
  if (excerpts.isEmpty) {
    b.writeln('Excerpts: (none found)');
  } else {
    b.writeln('Excerpts:');
    for (final e in excerpts) {
      b.writeln('[p.${e.page}]${multiDoc ? ' (${e.docName})' : ''}');
      b.writeln(e.text);
      b.writeln();
    }
  }
  b
    ..writeln('Question: ${question.trim()}')
    ..write('Answer:');

  // One source per (document, page): the first (document-order) excerpt on
  // that page supplies the snippet.
  final seen = <String>{};
  final sources = <DocSource>[];
  for (final e in excerpts) {
    if (!seen.add('${e.docId}:${e.page}')) continue;
    sources.add(
      DocSource(
        docName: e.docName,
        page: e.page,
        paged: e.paged,
        snippet: _snippet(e.text),
      ),
    );
  }
  return GroundedPrompt(b.toString(), sources);
}

String _snippet(String text, {int max = 160}) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.length <= max) return flat;
  return '${flat.substring(0, max).trimRight()}…';
}

final _citation = RegExp(r'\[\s*p\.?\s*([^\]]*)\]', caseSensitive: false);

/// The subset of [retrieved] whose page the [answer] cites as `[p.N]`; when
/// the answer cites nothing recognizable (e.g. "the document doesn't say"),
/// everything that was retrieved, so the user can still see what was read.
List<DocSource> citedSources(String answer, List<DocSource> retrieved) {
  final pages = <int>{};
  for (final m in _citation.allMatches(answer)) {
    for (final d in RegExp(r'\d+').allMatches(m.group(1)!)) {
      final n = int.tryParse(d.group(0)!);
      if (n != null) pages.add(n);
    }
  }
  final cited = [
    for (final s in retrieved)
      if (pages.contains(s.page)) s,
  ];
  return cited.isEmpty ? retrieved : cited;
}
