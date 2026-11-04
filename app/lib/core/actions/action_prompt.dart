/// How an Action (the old Workflow) rides a chat: the user's own text is the
/// user turn, and the instruction lives in the conversation's SYSTEM prompt,
/// under a one-line header. So the thread never shows the app-written prompt as
/// if the user had typed it, and the header gives the bubble its
/// "Action: Draft a reply" label, also after the chat is reopened.
///
///     Action: Draft a reply
///     Write a Warm reply to the message the user sends. ...
///
/// Plain strings and pure functions; `core` so both `features/workflows` (which
/// starts the chat) and `features/chat` (which shows it) can use it.
library;

const _prefix = 'Action: ';

/// Title of the Draft reply action; the thread opens the editable draft sheet
/// for conversations that carry it.
const draftReplyTitle = 'Draft a reply';

/// The system prompt of an action chat: [title] header, then [instruction].
String actionSystemPrompt({
  required String title,
  required String instruction,
}) => '$_prefix${title.trim()}\n${instruction.trim()}';

/// The action title of a conversation's [systemPrompt], or null when it is not
/// an action chat.
String? actionTitleOf(String systemPrompt) {
  if (!systemPrompt.startsWith(_prefix)) return null;
  final line = systemPrompt.substring(_prefix.length).split('\n').first.trim();
  return line.isEmpty ? null : line;
}

bool isDraftReplyChat(String systemPrompt) =>
    actionTitleOf(systemPrompt) == draftReplyTitle;

/// Tones the draft sheet offers.
const draftTones = ['Short', 'Warm', 'Formal'];

/// The instruction for a drafted reply in [tone].
String draftReplyInstruction(String tone) =>
    'Write a $tone reply to the message inside the <text> tags. Answer every '
    'question and request in it. Keep it brief and ready to send. Output only '
    'the reply, no preamble and no explanation. Never claim to attach, send '
    'or confirm availability or a time, and never promise anything that is '
    'not in the message.';

/// The system prompt of a Draft reply chat in [tone].
String draftReplySystemPrompt(String tone) => actionSystemPrompt(
  title: draftReplyTitle,
  instruction: draftReplyInstruction(tone),
);

/// The tone a draft chat is currently set to (default Warm).
String draftToneOf(String systemPrompt) {
  final m = RegExp(
    r'Write a (\w+) reply to the message',
  ).firstMatch(systemPrompt);
  final t = m?.group(1);
  return t != null && draftTones.contains(t) ? t : 'Warm';
}

// ---- user text delimiters ----------------------------------------------------

// A `<text>` tag in any spelling: `<text>`, `</text >`, `< /TEXT\n>`, with
// attributes in tag form (`name="value"`). Only tag-shaped input matches: prose
// such as `x < text and y > z` has no `=` attributes and is left alone. Every
// quantifier is bounded or unambiguous, so the match is linear.
final _textTag = RegExp(
  r'<\s*(?:/\s*)?text(?:\s+[A-Za-z_:][-\w:.]*\s*=\s*'
  r'(?:\x22[^\x22<>]{0,200}\x22|\x27[^\x27<>]{0,200}\x27|[^\s\x22\x27<>=]{1,200})){0,10}\s*/?>',
  caseSensitive: false,
);

/// [s] without text tags, repeated until none is left: removing one can join
/// the halves of another (`</te</text>xt>`).
String _withoutTextTags(String s) {
  var out = s;
  for (var i = 0; i < 8; i++) {
    final next = out.replaceAll(_textTag, '');
    if (next == out) return out;
    out = next;
  }
  // Still nesting after 8 passes: hostile. Drop the brackets outright.
  return out.replaceAll('<', '').replaceAll('>', '');
}

/// The user turn of an action chat: [text] between `<text>` tags, so a small
/// model can tell the material from the instruction (which lives only in the
/// system layer) and does not echo it. Tags inside [text] are dropped so it
/// cannot close the block early.
String wrapActionText(String text) =>
    '<text>\n${_withoutTextTags(text).trim()}\n</text>';

/// [reply] without any `<text>` tags the model copied into its answer.
String stripActionDelimiters(String reply) => _withoutTextTags(reply);

// ---- omissions -------------------------------------------------------------

final _askLead = RegExp(
  r'^(?:and\s+|also\s+|plus\s+)?(?:(?:hi|hey|hello|dear)\s+\w+[,!]?\s+)?'
  r'(?:please\s+|pls\s+|kindly\s+)?(?:also\s+)?'
  r'(?:can|could|would|will)\s+you\s+(?:also\s+|please\s+)?'
  r'|^(?:i|we)\s+need\s+you\s+to\s+'
  r'|^(?:please|pls|kindly)\s+(?:also\s+)?'
  r'|^let\s+me\s+know\s+(?:if|whether|when|about)?\s*'
  r'|^(?:also\s+)',
  caseSensitive: false,
);

final _senderPrefix = RegExp(r'^[^:\n.?!]{1,40}:\s+');

final _requestWord = RegExp(
  r'\b(?:please|pls|kindly|can you|could you|would you|will you|need you|'
  r'let me know|confirm|approve|review|send|share|call|reply|sign|update)\b',
  caseSensitive: false,
);

const _stop = {
  'the',
  'and',
  'for',
  'you',
  'your',
  'that',
  'this',
  'with',
  'from',
  'have',
  'will',
  'can',
  'could',
  'would',
  'also',
  'please',
  'when',
  'what',
  'which',
  'about',
  'there',
  'their',
  'them',
  'then',
  'than',
  'just',
  'into',
  'over',
  'some',
  'any',
  'are',
  'was',
  'were',
  'been',
  'let',
  'know',
};

List<String> _terms(String s) => [
  for (final w in s.toLowerCase().split(
    RegExp(r'[^\p{L}\p{N}]+', unicode: true),
  ))
    if (w.length >= 3 && !_stop.contains(w)) w,
];

/// Questions and requests in [source] that [draft] does not touch, as short
/// phrases ("review the vendor contract"), at most [max]. A rule check, not a
/// model: a sentence of the source that asks something (a question mark or a
/// request word) counts as covered when the draft uses at least half of its
/// key words (matched on their first five letters, so "approve" meets
/// "approved").
List<String> draftOmissions(String source, String draft, {int max = 3}) {
  // The Inbox pre-fills "Sender: body"; the sender is not part of any ask.
  source = source.trimLeft().replaceFirst(_senderPrefix, '');
  final draftTerms = _terms(draft);
  bool uses(String term) {
    final stem = term.length > 5 ? term.substring(0, 5) : term;
    return draftTerms.any((d) => d.startsWith(stem) || term.startsWith(d));
  }

  final out = <String>[];
  for (final raw in source.split(RegExp(r'(?<=[.?!])\s+|\n+'))) {
    final sentence = raw.trim();
    if (sentence.isEmpty) continue;
    if (!sentence.contains('?') && !_requestWord.hasMatch(sentence)) continue;
    final terms = _terms(sentence);
    if (terms.length < 2) continue;
    final used = terms.where(uses).length;
    if (used * 2 >= terms.length) continue;
    var phrase = sentence.replaceAll(RegExp(r'[?!.]+$'), '').trim();
    // "Also please review..." sheds one lead word at a time.
    for (var i = 0; i < 3; i++) {
      phrase = phrase.replaceFirst(_askLead, '').trim();
    }
    final words = phrase.split(RegExp(r'\s+'));
    if (words.length > 7) phrase = '${words.take(7).join(' ')}…';
    if (phrase.isEmpty) continue;
    out.add(phrase);
    if (out.length >= max) break;
  }
  return out;
}

/// "Didn't cover: a, b" or null when the draft covers everything it was asked.
String? omissionNote(String source, String draft) {
  final o = draftOmissions(source, draft);
  return o.isEmpty ? null : "Didn't cover: ${o.join('; ')}";
}

// ---- invented claims ------------------------------------------------------

/// A claim the draft makes that the message never asked for.
enum DraftInvention {
  attachment('Mentions an attachment. Check before sending'),
  availability("Says you're free. Check your calendar"),
  promise('Promises something. Check before sending');

  const DraftInvention(this.warning);
  final String warning;
}

final _claims = <DraftInvention, RegExp>{
  DraftInvention.attachment: RegExp(
    r'\battach\w*|\benclosed\b|\bnotes from\b|\bsending you\b',
    caseSensitive: false,
  ),
  DraftInvention.availability: RegExp(
    r"\bI am free\b|\bI'm free\b|\bavailable\b|\bworks for me\b|\bsee you at\b",
    caseSensitive: false,
  ),
  DraftInvention.promise: RegExp(
    r"\bI will send\b|\bI'll send\b|\bI will share\b|\bI'll share\b",
    caseSensitive: false,
  ),
};

/// The kinds of claim in [draft] that appear in neither the [source] message
/// nor [userEdits] (text the user typed themselves). Warns only; a rule check.
List<DraftInvention> draftInventions(
  String draft,
  String source, {
  String userEdits = '',
}) {
  final known = '$source\n$userEdits'.toLowerCase();
  return [
    for (final e in _claims.entries)
      if (e.value
          .allMatches(draft)
          .any((m) => !known.contains(m.group(0)!.toLowerCase())))
        e.key,
  ];
}

/// The sentences of [current] that are not in [generated]: what the user typed.
String userEditsOf(String generated, String current) {
  final had = generated.toLowerCase();
  return current
      .split(RegExp(r'(?<=[.?!])\s+|\n+'))
      .where(
        (s) => s.trim().isNotEmpty && !had.contains(s.trim().toLowerCase()),
      )
      .join('\n');
}

/// The label of the Draft sheet's open button: "Open in WhatsApp", or "Open
/// app" when the label is missing or just a package name.
String openAppLabel(String? app) {
  final a = app?.trim() ?? '';
  final pkg = RegExp(r'^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$', caseSensitive: false);
  return a.isEmpty || pkg.hasMatch(a) ? 'Open app' : 'Open in $a';
}
