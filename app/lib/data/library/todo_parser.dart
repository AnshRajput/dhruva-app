/// Turns the reply of the "Extract to-dos" action into a list of tasks.
///
/// The action asks for `- [ ] task` lines, so those are taken whenever they
/// are there. A small model sometimes answers with plain bullets instead; those
/// are accepted only when the whole reply is a bare list (at most one intro
/// line), so a paragraph of advice with one bullet in it never turns into
/// tasks. "No action items." and anything unparseable give an empty list, and
/// nothing is ever added without the user tapping the button that calls this.
library;

/// Most tasks taken from one reply, and the longest one kept.
const maxTodosPerReply = 20;
const maxTodoChars = 200;

final _checkbox = RegExp(r'^\s*(?:[-*•]\s*)?\[\s\]\s*(.+)$');
final _bullet = RegExp(r'^\s*(?:[-*•]|\d{1,2}[.)])\s+(.+)$');
final _noItems = RegExp(r'^no (?:action )?items?\.?$', caseSensitive: false);

List<String> parseTodos(String reply) {
  final lines = [
    for (final l in reply.split('\n'))
      if (l.trim().isNotEmpty) l,
  ];
  if (lines.isEmpty) return const [];

  var found = <String>[
    for (final l in lines) ?_checkbox.firstMatch(l)?.group(1),
  ];
  if (found.isEmpty) {
    final bullets = [for (final l in lines) _bullet.firstMatch(l)?.group(1)];
    final prose = bullets.where((b) => b == null).length;
    final intro = lines.first.trim();
    final onlyIntro =
        prose == 0 ||
        (prose == 1 && bullets.first == null && intro.endsWith(':'));
    if (onlyIntro) found = [for (final b in bullets) ?b];
  }

  final out = <String>[];
  for (final raw in found) {
    // Drop emphasis markers and a trailing period; keep "who/when" text.
    var t = raw.replaceAll(RegExp(r'\*\*|__|`'), '').trim();
    if (t.isEmpty || _noItems.hasMatch(t)) continue;
    // A checked-off or struck line is not an open task.
    if (t.startsWith('~~') || RegExp(r'^\[[xX]\]').hasMatch(t)) continue;
    if (t.length > maxTodoChars) {
      t = '${t.substring(0, maxTodoChars - 1).trimRight()}…';
    }
    if (!out.contains(t)) out.add(t);
    if (out.length == maxTodosPerReply) break;
  }
  return out;
}
