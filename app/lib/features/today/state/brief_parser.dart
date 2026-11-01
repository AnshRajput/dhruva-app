/// Turns the model's brief into something the UI can trust: sentences made of
/// plain and CITED spans. A cited span is the phrase right before a `[n]`
/// marker; the UI makes it tappable and opens fact n. A sentence with no valid
/// marker is DROPPED, because a claim that cannot be checked against a fact
/// must not be shown as the phone's own summary.
library;

/// A run of text. [cites] is empty for plain text, otherwise the fact numbers
/// (all valid) this phrase rests on.
final class BriefSpan {
  const BriefSpan(this.text, [this.cites = const []]);
  final String text;
  final List<int> cites;
  bool get isCited => cites.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is BriefSpan && other.text == text && _same(other.cites, cites);

  @override
  int get hashCode => Object.hash(text, Object.hashAll(cites));

  @override
  String toString() => 'BriefSpan($text, $cites)';
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

final class BriefSentence {
  const BriefSentence(this.spans);
  final List<BriefSpan> spans;
  String get plain => spans.map((s) => s.text).join().trim();
}

final class ParsedBrief {
  const ParsedBrief(this.sentences, {this.dropped = 0});
  final List<BriefSentence> sentences;

  /// Sentences thrown away for lacking a valid marker.
  final int dropped;
  bool get isEmpty => sentences.isEmpty;
}

/// Most sentences shown, whatever the model wrote.
const maxBriefSentences = 5;

final _marker = RegExp(r'\[\s*(\d{1,3}(?:\s*[,;]\s*\d{1,3})*)\s*\]');

/// Parses [raw] against the fact numbers that really exist ([validIds]).
///
/// Small models cite in different styles, so all of these work: markers LAST
/// ("Design sync at 9:30 [1]."), markers FIRST, one per line ("[1] Design sync
/// at 9:30."), stacked ("[1][2]"), mid-sentence, and a mix. A marker is never
/// absorbed into the previous sentence when sentence text follows it, unless
/// that sentence has no marker of its own yet ("9:30. [1] Ravi ...").
ParsedBrief parseBrief(
  String raw, {
  required Set<int> validIds,
  int maxSentences = maxBriefSentences,
}) {
  final text = raw
      .replaceAll(RegExp(r'<think>[\s\S]*?</think>'), ' ')
      .replaceAll(RegExp(r'<think>[\s\S]*$'), ' ');

  final sentences = <BriefSentence>[];
  final seen = <String>{};
  var dropped = 0;
  // Lines first: a line break is a sentence break, and it is what tells a
  // marker that leads the next line from one that trails this line.
  for (final rawLine in text.split(RegExp(r'\r?\n'))) {
    final line = rawLine
        .replaceFirst(RegExp(r'^\s*(?:[-*\u2022]|\d+[.)])\s+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (line.isEmpty) continue;
    for (final chunk in _splitSentences(line)) {
      final s = _toSentence(chunk, validIds);
      if (s == null) {
        dropped++;
        continue;
      }
      if (!seen.add(s.plain)) continue;
      if (sentences.length < maxSentences) sentences.add(s);
    }
  }
  return ParsedBrief(sentences, dropped: dropped);
}

/// Splits one line on `.`/`!`/`?` that end a sentence (followed by space or
/// the end, so "18.4L" and "9:30." inside a number stay whole). Markers right
/// after the punctuation stay with the NEXT sentence when text follows them
/// ("[1] A. [2] B."), and go to the previous one when nothing follows or that
/// sentence has no marker yet ("A. [1] B [2].").
List<String> _splitSentences(String text) {
  final out = <String>[];
  var start = 0;
  var i = 0;
  while (i < text.length) {
    final c = text[i];
    if (c == '.' || c == '!' || c == '?') {
      var j = i + 1;
      while (j < text.length && '.!?'.contains(text[j])) {
        j++;
      }
      var e = j;
      while (true) {
        var k = e;
        while (k < text.length && text[k] == ' ') {
          k++;
        }
        final m = _marker.matchAsPrefix(text, k);
        if (m == null) break;
        e = m.end;
      }
      if (e > j && (e >= text.length || text[e] == ' ')) {
        final textFollows = text.substring(e).trim().isNotEmpty;
        final prevCited = _marker.hasMatch(text.substring(start, j));
        if (!textFollows || !prevCited) j = e;
      }
      if (j >= text.length || text[j] == ' ') {
        out.add(text.substring(start, j).trim());
        start = j;
        i = j;
        continue;
      }
    }
    i++;
  }
  if (start < text.length) out.add(text.substring(start).trim());
  return out.where((s) => s.isNotEmpty).toList();
}

int? _validId(String raw, Set<int> validIds) {
  final n = int.tryParse(raw.trim());
  return n != null && validIds.contains(n) ? n : null;
}

List<int> _ids(Match m, Set<int> validIds) => [
  for (final p in m.group(1)!.split(RegExp(r'[,;]'))) ?_validId(p, validIds),
];

List<int> _union(List<int> a, List<int> b) => [
  ...a,
  for (final n in b)
    if (!a.contains(n)) n,
];

BriefSentence? _toSentence(String chunk, Set<int> validIds) {
  // Leading markers ("[1] Design sync ...") cite the text that follows them.
  var lead = <int>[];
  var body = chunk.trimLeft();
  while (true) {
    final m = _marker.matchAsPrefix(body);
    if (m == null) break;
    lead = _union(lead, _ids(m, validIds));
    body = body.substring(m.end).trimLeft();
  }
  if (body.isEmpty) return null;

  final spans = <BriefSpan>[];
  var pos = 0;
  var anyValid = false;

  void plain(String s) {
    if (s.isNotEmpty) spans.add(BriefSpan(s));
  }

  for (final m in _marker.allMatches(body)) {
    final ids = _ids(m, validIds);
    final before = body.substring(pos, m.start);
    pos = m.end;
    if (ids.isEmpty) {
      // An invented marker is not evidence; its text stays, un-linked.
      plain(before.trimRight());
      continue;
    }
    anyValid = true;
    if (before.trim().isEmpty && spans.isNotEmpty) {
      // "[1][2]": more evidence for the previous phrase.
      final last = spans.removeLast();
      spans.add(BriefSpan(last.text, _union(last.cites, ids)));
    } else {
      spans.add(BriefSpan(before.trimRight(), ids));
    }
  }
  plain(body.substring(pos));

  if (lead.isNotEmpty) {
    anyValid = true;
    if (spans.isNotEmpty && spans.first.isCited) {
      // "[1] A and B [2].": both markers cite the phrase before the second.
      spans[0] = BriefSpan(spans.first.text, _union(lead, spans.first.cites));
    } else {
      // The leading marker cites the whole sentence; closing punctuation
      // stays plain.
      final first = spans.removeAt(0);
      final t = first.text;
      final cut = t.replaceFirst(RegExp(r'[\s.!?]+$'), '').length;
      final rest = <BriefSpan>[
        if (cut > 0) BriefSpan(t.substring(0, cut), lead),
        if (cut < t.length) BriefSpan(t.substring(cut)),
      ];
      spans.insertAll(0, rest);
    }
  }
  if (!anyValid || spans.isEmpty) return null;
  if (spans.every((s) => !s.isCited)) return null;

  // Tidy: the first span has no leading space.
  final first = spans.first;
  spans[0] = BriefSpan(first.text.trimLeft(), first.cites);
  return BriefSentence(spans);
}
