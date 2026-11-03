/// Spots a reply stuck in a loop ("Ana Costa, Ana Costa, with Ana Costa...").
/// Pure text rules; the reply is only inspected, never acted on.
library;

/// `MessageInfo.errorKind` of a reply that looped. The row is an error with no
/// text, so the thread shows [degenerateNotice] with a retry and no source
/// chips lend the loop any authority.
const degenerateErrorKind = 'DegenerateReply';

/// What the thread shows instead of a looped answer.
const degenerateNotice =
    'That answer repeated itself. Try again, or pick a bigger model.';

final _split = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

List<String> _words(String s) =>
    s.toLowerCase().split(_split).where((w) => w.isNotEmpty).toList();

Map<String, int> _counts(List<String> w, int n) {
  final out = <String, int>{};
  for (var i = 0; i + n <= w.length; i++) {
    out.update(w.sublist(i, i + n).join(' '), (c) => c + 1, ifAbsent: () => 1);
  }
  return out;
}

/// True while streaming when a run of four or more words has appeared
/// [times] or more times: the model is looping, so generation can stop.
bool hasRepeatLoop(String text, {int n = 4, int times = 3}) =>
    _counts(_words(text), n).values.any((c) => c >= times);

/// True when a finished reply is mostly repetition: at least 12 words and
/// either under half of its four-word runs are unique, or one pair of words
/// ("Ana Costa") fills over a third of the reply in four or more places.
/// A name mentioned twice, or a list that names each person a few times, is
/// not enough.
// ponytail: word-pair heuristic, tuned on one real loop; revisit with more.
bool isDegenerateReply(String text) {
  final w = _words(text);
  if (w.length < 12) return false;
  final grams = _counts(w, 4);
  final total = w.length - 3;
  if (grams.length / total < 0.5) return true;
  final top = _counts(w, 2).values.fold<int>(0, (a, b) => a > b ? a : b);
  return top >= 4 && top * 2 / w.length > 0.35;
}
