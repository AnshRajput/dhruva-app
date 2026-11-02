/// Catches the reply a small model gives when it parrots the grounded prompt
/// back instead of answering: the sources preamble, the `<sources>` block or
/// its `[n] event | ...` rows. Such a reply is replaced by [echoNotice] with
/// the source chips left under it, so the user never reads the app's own
/// instructions or a raw dump as if it were an answer.
///
/// Pure text rules; the reply is only inspected, never acted on.
library;

import '../../../core/actions/action_prompt.dart' show actionTitleOf;
import '../../../data/connectors/ask_sources.dart'
    show askInstruction, askInstructionWithDocs;
import '../../../data/connectors/sources_block.dart' show sourcesPreamble;

/// `MessageInfo.errorKind` of an Action reply that echoed its own instruction.
/// The row is an error with no text, so the thread shows a retry card and no
/// reply-level action (Replace selected text, Edit draft, Copy) can touch it.
const actionEchoErrorKind = 'ActionEchoFailure';

/// What the thread shows instead of an echoed prompt.
const echoNotice = "I couldn't answer that from your sources. Here they are.";

final _row = RegExp(
  r'(?:^|\n)\s*\[\d+\]\s+(?:event|notification|file|contact|mail)\b\s*\|',
  caseSensitive: false,
);

final _words = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

List<String> _tokens(String s) => s
    .toLowerCase()
    .split(_words)
    .where((w) => w.isNotEmpty)
    .toList(growable: false);

Set<String> _shingles(List<String> w, int n) => {
  for (var i = 0; i + n <= w.length; i++) w.sublist(i, i + n).join(' '),
};

String _norm(String s) => _tokens(s).join(' ');

/// Meta-sentences a small model parrots from an Action's system layer instead
/// of doing the task. Matched on normalised words, anywhere in the reply.
const _actionMeta = [
  "the user's next message",
  'the text to work on',
  'text to work on',
  'the message the user sends',
  'the text is inside',
  'text tags',
  'reply with only the result',
  'output only the reply',
  'no preamble and no explanation',
];

/// True when [reply] to an Action chat (one whose [systemPrompt] carries the
/// `Action:` header) is the Action's own instruction, or a meta-sentence about
/// it ("The user's next message is the text to work on."), rather than a
/// result. Three rules: a meta-sentence anywhere; a whole instruction
/// sentence of four or more words anywhere; or a reply made mostly of the
/// instruction's four-word runs. Whatever the user's own [userText] contains
/// is exempt, so summarising a document that quotes such words is no echo.
///
/// Pure text rules; the reply is only inspected, never acted on.
bool isActionEcho(String reply, String systemPrompt, {String userText = ''}) {
  if (actionTitleOf(systemPrompt) == null) return false;
  final r = _norm(reply);
  if (r.isEmpty) return false;
  final padded = ' $r ';
  final user = ' ${_norm(userText)} ';
  bool echoes(String phrase) {
    final n = _norm(phrase);
    if (n.isEmpty) return false;
    return padded.contains(' $n ') && !user.contains(' $n ');
  }

  if (_actionMeta.any(echoes)) return true;
  final nl = systemPrompt.indexOf('\n');
  final instruction = nl < 0 ? '' : systemPrompt.substring(nl + 1);
  for (final sentence in instruction.split(RegExp(r'(?<=[.!?])\s+|\n+'))) {
    if (_tokens(sentence).length >= 4 && echoes(sentence)) return true;
  }
  final w = _tokens(reply);
  if (w.length >= 8) {
    final mine = _shingles(w, 4);
    final theirs = _shingles(_tokens(instruction), 4);
    if (mine.isNotEmpty &&
        mine.where(theirs.contains).length / mine.length > 0.5) {
      return true;
    }
  }
  return false;
}

final _sourcesBody = RegExp(r'<sources>.*?</sources>', dotAll: true);
final _excerptsBody = RegExp(
  r'(^|\n)Excerpts:.*?(?=\nQuestion:|$)',
  dotAll: true,
);

/// [prompt] minus its quoted data (the `<sources>` block body, the document
/// `Excerpts:` section). A correct answer quotes its source, so overlap with
/// the data is an answer, not an echo; only the app's own wording counts.
/// Raw rows and the tags themselves are still caught by the rules above.
String scaffoldOnly(String prompt) =>
    prompt.replaceAll(_sourcesBody, ' ').replaceAll(_excerptsBody, ' ');

/// True when [reply] is the grounded prompt (or its sources) echoed back.
/// [prompt] is the grounded prompt that was sent; with it, a reply made mostly
/// of its text (over half of the reply's four-word runs) is also an echo.
bool isScaffoldEcho(String reply, {String? prompt}) {
  final t = reply.trim();
  if (t.isEmpty) return false;
  final lower = t.toLowerCase();
  if (lower.contains('<sources>') || lower.contains('</sources>')) return true;
  if (_row.hasMatch(t)) return true;
  final head = _norm(t.length > 160 ? t.substring(0, 160) : t);
  for (final lead in [
    sourcesPreamble,
    askInstruction,
    askInstructionWithDocs,
  ]) {
    final l = _norm(lead);
    final n = l.length < 40 ? l.length : 40;
    if (head.startsWith(l.substring(0, n))) return true;
  }
  if (prompt != null) {
    final w = _tokens(t);
    if (w.length >= 12) {
      final mine = _shingles(w, 4);
      final theirs = _shingles(_tokens(scaffoldOnly(prompt)), 4);
      if (mine.isNotEmpty) {
        final shared = mine.where(theirs.contains).length;
        if (shared / mine.length > 0.5) return true;
      }
    }
  }
  return false;
}
