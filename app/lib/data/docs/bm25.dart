/// Keyword retrieval for chat-with-a-document: a simple tokenizer plus Okapi
/// BM25 scoring in pure Dart. No embedding model, no native code.
library;

import 'dart:math' as math;

/// Common English words that carry no retrieval signal.
const _stopwords = <String>{
  'a',
  'about',
  'above',
  'after',
  'again',
  'all',
  'also',
  'am',
  'an',
  'and',
  'any',
  'are',
  'as',
  'at',
  'be',
  'because',
  'been',
  'before',
  'being',
  'below',
  'between',
  'both',
  'but',
  'by',
  'can',
  'could',
  'did',
  'do',
  'does',
  'doing',
  'down',
  'during',
  'each',
  'few',
  'for',
  'from',
  'further',
  'had',
  'has',
  'have',
  'having',
  'he',
  'her',
  'here',
  'hers',
  'him',
  'his',
  'how',
  'i',
  'if',
  'in',
  'into',
  'is',
  'it',
  'its',
  'just',
  'me',
  'more',
  'most',
  'my',
  'no',
  'nor',
  'not',
  'now',
  'of',
  'off',
  'on',
  'once',
  'only',
  'or',
  'other',
  'our',
  'ours',
  'out',
  'over',
  'own',
  'same',
  'she',
  'should',
  'so',
  'some',
  'such',
  'than',
  'that',
  'the',
  'their',
  'theirs',
  'them',
  'then',
  'there',
  'these',
  'they',
  'this',
  'those',
  'through',
  'to',
  'too',
  'under',
  'until',
  'up',
  'very',
  'was',
  'we',
  'were',
  'what',
  'when',
  'where',
  'which',
  'while',
  'who',
  'whom',
  'why',
  'will',
  'with',
  'would',
  'you',
  'your',
  'yours',
};

// \p{M} (combining marks) stays inside a word: Devanagari/Tamil/Thai vowel
// signs are marks, and splitting on them shatters "पार्टी" into 1-character
// tokens that the length filter then drops.
final _nonWord = RegExp(r'[^\p{L}\p{N}\p{M}]+', unicode: true);

/// Lowercases [text], splits on anything that is not a letter or digit, drops
/// stopwords and 1-character tokens, and folds a plain plural `s`.
///
/// ponytail: the plural fold is the whole "stemmer"; swap in Porter if recall
/// on real documents turns out to need it.
List<String> tokenize(String text) {
  final out = <String>[];
  for (final raw in text.toLowerCase().split(_nonWord)) {
    if (raw.length < 2 || _stopwords.contains(raw)) continue;
    out.add(_fold(raw));
  }
  return out;
}

String _fold(String t) {
  if (t.length > 3 && t.endsWith('s') && !t.endsWith('ss')) {
    return t.substring(0, t.length - 1);
  }
  return t;
}

/// A chunk index with its BM25 score.
final class ScoredChunk {
  final int index;
  final double score;
  const ScoredChunk(this.index, this.score);
}

/// BM25 index over a fixed list of chunk texts. Build once per document set
/// (tokenizing is the expensive part), then call [search] per question.
final class Bm25Index {
  static const _k1 = 1.5;
  static const _b = 0.75;

  final List<Map<String, int>> _termFreqs;
  final List<int> _lengths;
  final Map<String, int> _docFreq;
  final double _avgLength;

  Bm25Index._(this._termFreqs, this._lengths, this._docFreq, this._avgLength);

  factory Bm25Index(List<String> texts) {
    final termFreqs = <Map<String, int>>[];
    final lengths = <int>[];
    final docFreq = <String, int>{};
    var total = 0;
    for (final text in texts) {
      final tokens = tokenize(text);
      final tf = <String, int>{};
      for (final t in tokens) {
        tf[t] = (tf[t] ?? 0) + 1;
      }
      for (final t in tf.keys) {
        docFreq[t] = (docFreq[t] ?? 0) + 1;
      }
      termFreqs.add(tf);
      lengths.add(tokens.length);
      total += tokens.length;
    }
    return Bm25Index._(
      termFreqs,
      lengths,
      docFreq,
      texts.isEmpty ? 0 : total / texts.length,
    );
  }

  int get length => _termFreqs.length;

  /// Chunks with a positive score for [query], best first (ties keep
  /// document order). Empty when the query has no usable keywords or nothing
  /// matches.
  List<ScoredChunk> search(String query) {
    final terms = tokenize(query).toSet();
    if (terms.isEmpty || _termFreqs.isEmpty) return const [];
    final n = _termFreqs.length;
    final scored = <ScoredChunk>[];
    for (var i = 0; i < n; i++) {
      final tf = _termFreqs[i];
      var score = 0.0;
      for (final term in terms) {
        final f = tf[term];
        if (f == null) continue;
        final df = _docFreq[term]!;
        final idf = math.log(1 + (n - df + 0.5) / (df + 0.5));
        final norm = _avgLength == 0 ? 1.0 : _lengths[i] / _avgLength;
        score += idf * (f * (_k1 + 1)) / (f + _k1 * (1 - _b + _b * norm));
      }
      if (score > 0) scored.add(ScoredChunk(i, score));
    }
    scored.sort((a, b) {
      final c = b.score.compareTo(a.score);
      return c != 0 ? c : a.index.compareTo(b.index);
    });
    return scored;
  }
}
