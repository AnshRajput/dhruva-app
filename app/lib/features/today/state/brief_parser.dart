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
ParsedBrief parseBrief(
  String raw, {
  required Set<int> validIds,
  int maxSentences = maxBriefSentences,
}) {
  var text = raw
      .replaceAll(RegExp(r'<think>[\s\S]*?</think>'), ' ')
      .replaceAll(RegExp(r'<think>[\s\S]*$'), ' ');
  // One paragraph: drop list bullets / numbering, join lines.
  text = text
      .split('\n')
      .map((l) => l.replaceFirst(RegExp(r'^\s*(?:[-*•]|\d+[.)])\s+'), ''))
      .join(' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  final sentences = <BriefSentence>[];
  final seen = <String>{};
  var dropped = 0;
  for (final chunk in _splitSentences(text)) {
    final s = _toSentence(chunk, validIds);
    if (s == null) {
      dropped++;
      continue;
    }
    if (!seen.add(s.plain)) continue;
    if (sentences.length < maxSentences) sentences.add(s);
  }
  return ParsedBrief(sentences, dropped: dropped);
}

/// Splits on `.`/`!`/`?` that end a sentence (followed by space or the end,
/// so "18.4L" and "9:30." inside a number stay whole), keeping markers that
/// trail the punctuation ("... 9:30. [1] Ravi ...") with the sentence they
/// belong to.
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
      // Absorb markers that trail the punctuation.
      while (true) {
        var k = j;
        while (k < text.length && text[k] == ' ') {
          k++;
        }
        final m = _marker.matchAsPrefix(text, k);
        if (m == null) break;
        j = m.end;
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

BriefSentence? _toSentence(String chunk, Set<int> validIds) {
  final spans = <BriefSpan>[];
  var pos = 0;
  var anyValid = false;

  void plain(String s) {
    if (s.isNotEmpty) spans.add(BriefSpan(s));
  }

  for (final m in _marker.allMatches(chunk)) {
    final ids = [
      for (final p in m.group(1)!.split(RegExp(r'[,;]')))
        ?_validId(p, validIds),
    ];
    final before = chunk.substring(pos, m.start);
    pos = m.end;
    if (ids.isEmpty) {
      // An invented marker is not evidence; its text stays, un-linked.
      plain(before.trimRight());
      continue;
    }
    anyValid = true;
    if (before.trim().isEmpty && spans.isNotEmpty && spans.last.isCited) {
      // "[1][2]": more evidence for the previous phrase.
      final last = spans.removeLast();
      spans.add(
        BriefSpan(last.text, [
          ...last.cites,
          for (final n in ids)
            if (!last.cites.contains(n)) n,
        ]),
      );
    } else {
      spans.add(BriefSpan(before.trimRight(), ids));
    }
  }
  plain(chunk.substring(pos));
  if (!anyValid) return null;

  // Tidy: the first span has no leading space; spacing before punctuation.
  final first = spans.first;
  spans[0] = BriefSpan(first.text.trimLeft(), first.cites);
  return BriefSentence(spans);
}
