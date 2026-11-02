/// Catches the reply a small model gives when it parrots the grounded prompt
/// back instead of answering: the sources preamble, the `<sources>` block or
/// its `[n] event | ...` rows. Such a reply is replaced by [echoNotice] with
/// the source chips left under it, so the user never reads the app's own
/// instructions or a raw dump as if it were an answer.
///
/// Pure text rules; the reply is only inspected, never acted on.
library;

import '../../../data/connectors/ask_sources.dart'
    show askInstruction, askInstructionWithDocs;
import '../../../data/connectors/sources_block.dart' show sourcesPreamble;

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
      final theirs = _shingles(_tokens(prompt), 4);
      if (mine.isNotEmpty) {
        final shared = mine.where(theirs.contains).length;
        if (shared / mine.length > 0.5) return true;
      }
    }
  }
  return false;
}
