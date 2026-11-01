/// The strict check a model's rewrite of the brief must pass before anyone sees
/// it. Small on-device models invent: a sample sentence in a prompt comes back
/// as "your first meeting is Standup at 9:00", with a perfectly valid `[1]`
/// marker, so a tap would open an unrelated event. Markers prove nothing; the
/// words do.
///
/// A rewrite is accepted only if EVERY sentence
///  * carries at least one marker, and every marker names a real fact,
///  * uses no number or time that is absent from the facts it cites (12 and
///    24 hour clocks, "9:00", "9 AM" and "09:00" all match each other; number
///    words from two to twelve count as numbers), and
///  * uses no capitalised word (a name, an app, a title) that is absent from
///    those facts, except the sentence-initial common words and the small
///    allowlist below (You, Today, weekdays, months, the user's own name).
///
/// One failure rejects the whole rewrite: the caller keeps the rule-written
/// brief and shows "Kept the checked version".
library;

// ignore_for_file: equal_elements_in_set

import 'brief_facts.dart';
import 'brief_parser.dart';

/// Sentence-initial words that are only English grammar, not claims.
final _commonInitial = <String>{
  'a',
  'an',
  'the',
  'this',
  'that',
  'these',
  'those',
  'it',
  'its',
  'there',
  'here',
  'you',
  'your',
  'youre',
  'youve',
  'yours',
  'we',
  'i',
  'they',
  'he',
  'she',
  'then',
  'after',
  'before',
  'also',
  'and',
  'but',
  'so',
  'or',
  'meanwhile',
  'otherwise',
  'overall',
  'first',
  'next',
  'last',
  'later',
  'finally',
  'today',
  'tomorrow',
  'tonight',
  'now',
  'still',
  'just',
  'when',
  'while',
  'if',
  'as',
  'because',
  'since',
  'with',
  'in',
  'on',
  'at',
  'by',
  'for',
  'from',
  'to',
  'until',
  'heads',
  'up',
  'nothing',
  'no',
  'none',
  'nobody',
  'all',
  'both',
  'plus',
  'expect',
  'start',
  'starts',
  'starting',
  'plan',
  'keep',
  'remember',
  'dont',
  'quiet',
  'busy',
  'free',
  'light',
  'clear',
  'good',
  'morning',
  'afternoon',
  'evening',
  'night',
  'hi',
  'hello',
  'hey',
  'looks',
  'looking',
  'make',
  'take',
  'get',
  'check',
  'reply',
  'replies',
  'waiting',
  'wait',
  'some',
  'most',
  'many',
  'few',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
  'ten',
  'one',
  'once',
  'twice',
  'half',
  'more',
  'another',
  'other',
  'others',
  'what',
  'who',
  'where',
  'which',
  'every',
  'each',
  'any',
  'on',
  'over',
  'between',
  'around',
  'about',
  'that',
  'thats',
  'whats',
  'lets',
  'let',
  'enjoy',
  'have',
  'has',
  'had',
  'is',
  'are',
  'was',
  'were',
  'be',
  'do',
  'does',
  'not',
  'only',
  'even',
  'soon',
  'later',
  'earlier',
  'ready',
  'set',
  'time',
  'day',
  'week',
  'weekend',
  'meeting',
  'meetings',
  'event',
  'events',
  'message',
  'messages',
  'notification',
  'notifications',
  'calendar',
};

/// Capitalised words that are fine anywhere in a sentence.
const _alwaysAllowed = {
  'you',
  'your',
  'today',
  'tomorrow',
  'tonight',
  'i',
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
  'mon',
  'tue',
  'wed',
  'thu',
  'fri',
  'sat',
  'sun',
  'january',
  'february',
  'march',
  'april',
  'may',
  'june',
  'july',
  'august',
  'september',
  'october',
  'november',
  'december',
  'jan',
  'feb',
  'mar',
  'apr',
  'jun',
  'jul',
  'aug',
  'sep',
  'sept',
  'oct',
  'nov',
  'dec',
};

const _numberWords = {
  'two': '2',
  'three': '3',
  'four': '4',
  'five': '5',
  'six': '6',
  'seven': '7',
  'eight': '8',
  'nine': '9',
  'ten': '10',
  'eleven': '11',
  'twelve': '12',
  'twice': '2',
};

/// "9:00", "09:00 PM", "9 am", "9pm". Group 1/2 = h:mm, 3 = its suffix;
/// 4 = bare hour, 5 = its suffix.
final _time = RegExp(
  r'\b(\d{1,2}):(\d{2})\s*(?:([ap])\.?m\b\.?)?|\b(\d{1,2})\s*([ap])\.?m\b\.?',
  caseSensitive: false,
);
final _number = RegExp(r'\d+(?:[.,]\d+)*');
final _word = RegExp(r"[\p{L}\p{M}][\p{L}\p{M}'’\-]*", unicode: true);
final _marker = RegExp(r'\[\s*(\d{1,3}(?:\s*[,;]\s*\d{1,3})*)\s*\]');

/// A time found in text: minutes since midnight, and whether it said AM/PM
/// (otherwise a 12 h hour could be either half of the day).
typedef _Clock = ({int minutes, bool explicit});

List<_Clock> _times(String text) {
  final out = <_Clock>[];
  for (final m in _time.allMatches(text)) {
    final bare = m.group(4) != null;
    final h = int.parse(bare ? m.group(4)! : m.group(1)!);
    final min = bare ? 0 : int.parse(m.group(2)!);
    final suffix = (bare ? m.group(5) : m.group(3))?.toLowerCase();
    if (h > 24 || min > 59) continue;
    var h24 = h % 24;
    if (suffix != null) {
      h24 = h % 12 + (suffix == 'p' ? 12 : 0);
    }
    out.add((minutes: h24 * 60 + min, explicit: suffix != null || h > 12));
  }
  return out;
}

Set<String> _numbers(String text) {
  final bare = text.replaceAll(_time, ' ');
  final out = <String>{
    for (final m in _number.allMatches(bare)) m.group(0)!.replaceAll(',', ''),
  };
  for (final w in _word.allMatches(bare)) {
    final n = _numberWords[w.group(0)!.toLowerCase()];
    if (n != null) out.add(n);
  }
  return out;
}

String _plainWord(String w) {
  var s = w.toLowerCase().replaceAll('’', "'");
  if (s.endsWith("'s")) s = s.substring(0, s.length - 2);
  return s.replaceAll("'", '');
}

/// Lowercase word parts of [text] (hyphenated words split), apostrophes gone.
Set<String> _words(String text) => {
  for (final m in _word.allMatches(text.replaceAll(_time, ' ')))
    for (final p in _plainWord(m.group(0)!).split('-'))
      if (p.isNotEmpty) p,
};

bool _isCapitalised(String w) {
  final c = w.runes.first;
  final s = String.fromCharCode(c);
  return s != s.toLowerCase() && s == s.toUpperCase();
}

/// Why [sentence] is not backed by [factsText], or null when it is. [names]
/// are extra allowed words (the user's own name).
String? ungrounded(
  String sentence,
  String factsText, {
  Set<String> names = const {},
}) {
  // Times: must be a time in the facts, 12/24 h agnostic.
  final factTimes = _times(factsText);
  final exact = {for (final f in factTimes) f.minutes};
  final half = {for (final f in factTimes) f.minutes % 720};
  for (final c in _times(sentence)) {
    final ok = c.explicit
        ? exact.contains(c.minutes)
        : half.contains(c.minutes % 720);
    if (!ok) return 'a time that is not in your day';
  }
  // Other numbers.
  final factNumbers = _numbers(factsText);
  for (final n in _numbers(sentence)) {
    if (!factNumbers.contains(n)) return 'the number $n';
  }
  // Names and other capitalised words.
  final factWords = _words(factsText);
  final allowed = {for (final n in names) ..._words(n)};
  final plain = sentence.replaceAll(_time, ' ');
  var first = true;
  for (final m in _word.allMatches(plain)) {
    final raw = m.group(0)!;
    final isFirst = first;
    first = false;
    if (!_isCapitalised(raw)) continue;
    final w = _plainWord(raw);
    if (w.isEmpty) continue;
    if (_alwaysAllowed.contains(w) || allowed.contains(w)) continue;
    if (isFirst && _commonInitial.contains(w)) continue;
    if (w.split('-').every((p) => factWords.contains(p))) continue;
    return 'the word "$raw"';
  }
  return null;
}

/// The verdict on a rewrite.
final class RewriteCheck {
  const RewriteCheck.accepted(this.sentences) : reason = null;
  const RewriteCheck.rejected(this.reason) : sentences = const [];

  /// The rewrite as cited spans; empty when rejected.
  final List<BriefSentence> sentences;

  /// Why it was rejected (for logs and tests; never shown as model text).
  final String? reason;

  bool get ok => reason == null;
}

/// Checks the model's [raw] text against [facts].
RewriteCheck checkRewrite(
  String raw,
  List<BriefFact> facts, {
  Set<String> names = const {},
}) {
  final ids = {for (final f in facts) f.n};
  final cleaned = raw
      .replaceAll(RegExp(r'<think>[\s\S]*?</think>'), ' ')
      .replaceAll(RegExp(r'<think>[\s\S]*$'), ' ')
      // "Here is your brief:" style intros are not claims.
      .split(RegExp(r'\r?\n'))
      .where((l) => !l.trim().endsWith(':') || _marker.hasMatch(l))
      .join('\n');

  // An invented marker is an invented citation.
  for (final m in _marker.allMatches(cleaned)) {
    for (final p in m.group(1)!.split(RegExp(r'[,;]'))) {
      if (!ids.contains(int.parse(p.trim()))) {
        return const RewriteCheck.rejected(
          'a citation to a fact that is not there',
        );
      }
    }
  }

  final parsed = parseBrief(cleaned, validIds: ids, maxSentences: 50);
  if (parsed.isEmpty) return const RewriteCheck.rejected('nothing citable');
  if (parsed.dropped > 0) {
    return const RewriteCheck.rejected('a sentence without a citation');
  }
  if (parsed.sentences.length > maxBriefSentences) {
    return const RewriteCheck.rejected('too long');
  }
  for (final s in parsed.sentences) {
    final cites = {for (final span in s.spans) ...span.cites};
    final text = [
      for (final f in facts)
        if (cites.contains(f.n)) f.text,
    ].join(' \n ');
    final why = ungrounded(s.plain, text, names: names);
    if (why != null) {
      return RewriteCheck.rejected('"${s.plain}" uses $why');
    }
  }
  return RewriteCheck.accepted(parsed.sentences);
}
