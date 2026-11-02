/// Ask grounded in the user's own data: which sources a question searches
/// (rules only, no model), the grounded prompt, and the citation chips under
/// the answer. Pure Dart: no I/O, no Flutter.
///
/// Untrusted text (calendar, notification, file, later mail) reaches the
/// prompt ONLY through `buildSourcesBlock` (sources_block.dart): delimited,
/// numbered, escaped. Nothing here lets item text trigger an action.
library;

import 'dart:convert';

import 'connector.dart';
import 'local_time.dart';
import 'sources_block.dart';

export 'local_time.dart' show itemWhenText, shortDate, shortTime, whenText;

/// The "Search in" chips. [docs] means the documents attached to the chat.
enum AskSource { mail, calendar, contacts, files, docs }

extension AskSourceX on AskSource {
  String get label => switch (this) {
    AskSource.mail => 'Mail',
    AskSource.calendar => 'Calendar',
    AskSource.contacts => 'Contacts',
    AskSource.files => 'Files',
    AskSource.docs => 'Docs',
  };

  /// The connector that fills this source (`items.source`), or null for
  /// [AskSource.docs] (chat attachments are not a connector). Mail has no
  /// connector yet; its id is reserved for Gmail (0.7b).
  String? get connectorId => switch (this) {
    AskSource.mail => ConnectorIds.mail,
    AskSource.calendar => ConnectorIds.calendar,
    AskSource.contacts => ConnectorIds.contacts,
    AskSource.files => ConnectorIds.folder,
    AskSource.docs => null,
  };
}

/// Sources that read connector items (everything but [AskSource.docs]).
Set<AskSource> connectorSourcesOf(Iterable<AskSource> s) => {
  for (final x in s)
    if (x != AskSource.docs) x,
};

AskSource? askSourceFromId(String id) {
  for (final s in AskSource.values) {
    if (s.name == id) return s;
  }
  return null;
}

/// Parses `sources=calendar,contacts,files` from a route. Unknown ids are
/// ignored; null/empty gives an empty set.
Set<AskSource> parseAskSources(String? csv) => {
  for (final id in (csv ?? '').split(','))
    ?askSourceFromId(id.trim().toLowerCase()),
};

/// What the user chose in the "Search in" row: Auto (rules pick from the
/// question) or an explicit set (possibly empty = "just the model").
final class AskSourceSelection {
  final bool auto;
  final Set<AskSource> pinned;
  const AskSourceSelection({this.auto = true, this.pinned = const {}});

  static const autoSelection = AskSourceSelection();

  AskSourceSelection copyWith({bool? auto, Set<AskSource>? pinned}) =>
      AskSourceSelection(
        auto: auto ?? this.auto,
        pinned: pinned ?? this.pinned,
      );

  /// The sources this question will search, before availability is applied.
  Set<AskSource> resolve({
    required String question,
    Iterable<String> contactNames = const [],
    bool hasDocuments = false,
  }) {
    final chosen = auto
        ? autoSelectSources(
            question,
            contactNames: contactNames,
            hasDocuments: hasDocuments,
          )
        : pinned;
    return hasDocuments
        ? chosen
        : {
            for (final s in chosen)
              if (s != AskSource.docs) s,
          };
  }

  @override
  bool operator ==(Object other) =>
      other is AskSourceSelection &&
      other.auto == auto &&
      other.pinned.length == pinned.length &&
      other.pinned.containsAll(pinned);

  @override
  int get hashCode => Object.hash(auto, Object.hashAllUnordered(pinned));
}

// ---- Auto rules ------------------------------------------------------------

RegExp _words(String alternatives) =>
    RegExp('\\b(?:$alternatives)\\b', caseSensitive: false);

final _calendarStrong = _words(
  r'meeting|meetings|meet|calendar|schedule|scheduled|agenda|appointment|'
  r'appointments|event|events|tomorrow|tonight|standup|invite|invites',
);

/// Ambiguous on their own ("when was Rome founded"), so they only count when
/// the question is about the user (my / me / I / we).
final _calendarWeak = _words(r'when|free|busy|time|today');
final _personal = _words(r"my|me|i|i'm|we|our|mine");
final _fileWords = _words(
  r'file|files|note|notes|doc|docs|document|documents|pdf|folder|spreadsheet',
);
final _mailWords = _words(r'email|emails|mail|inbox|message|messages|thread');

/// Names from [contactNames] that [question] mentions (whole-word, first or
/// full name, case-insensitive, at least 3 letters).
List<String> mentionedContacts(String question, Iterable<String> contactNames) {
  final out = <String>[];
  for (final full in contactNames) {
    final candidates = {full, ...full.split(RegExp(r'\s+'))};
    for (final c in candidates) {
      if (c.trim().length < 3) continue;
      final re = RegExp(
        '(?<![\\p{L}\\p{N}])${RegExp.escape(c.trim())}(?![\\p{L}\\p{N}])',
        caseSensitive: false,
        unicode: true,
      );
      if (re.hasMatch(question)) {
        out.add(full);
        break;
      }
    }
  }
  return out;
}

/// Auto: picks sources from the question with plain rules (no model call):
///  * meeting / schedule words (or "when/free/time" about me) -> Calendar
///  * a known contact's name -> Contacts + Calendar
///  * file / note / document words -> Files + Docs
///  * email words -> Mail
///  * documents attached to the chat -> Docs (as before)
///  * otherwise nothing: a plain, ungrounded answer.
Set<AskSource> autoSelectSources(
  String question, {
  Iterable<String> contactNames = const [],
  bool hasDocuments = false,
}) {
  final out = <AskSource>{};
  final q = question.trim();
  if (q.isNotEmpty) {
    if (_calendarStrong.hasMatch(q) ||
        (_calendarWeak.hasMatch(q) && _personal.hasMatch(q))) {
      out.add(AskSource.calendar);
    }
    if (mentionedContacts(q, contactNames).isNotEmpty) {
      out.addAll({AskSource.contacts, AskSource.calendar});
    }
    if (_fileWords.hasMatch(q)) out.addAll({AskSource.files, AskSource.docs});
    if (_mailWords.hasMatch(q)) out.add(AskSource.mail);
  }
  if (hasDocuments) out.add(AskSource.docs);
  return out;
}

// ---- chip availability -----------------------------------------------------

/// How one source chip is offered.
enum AskChipAvailability {
  /// Selectable.
  ready,

  /// Not connected: the chip shows "Connect" and opens that connector's card.
  needsConnect,
}

/// Chips to show, in order. Mail is hidden until a mail connector exists
/// ([present] lists connector ids that exist on this platform, with whether
/// each is connected). Docs only appears when the chat has documents.
List<({AskSource source, AskChipAvailability availability})> askChips({
  required Map<String, bool> connectors,
  required bool hasDocuments,
}) {
  final out = <({AskSource source, AskChipAvailability availability})>[];
  for (final s in AskSource.values) {
    if (s == AskSource.docs) {
      if (hasDocuments) {
        out.add((source: s, availability: AskChipAvailability.ready));
      }
      continue;
    }
    final connected = connectors[s.connectorId];
    if (connected == null) continue; // not offered on this platform / yet
    out.add((
      source: s,
      availability: connected
          ? AskChipAvailability.ready
          : AskChipAvailability.needsConnect,
    ));
  }
  return out;
}

/// The settings route a "Connect" tap opens: the connector's card. The
/// `connector` query lets the Connectors screen scroll to / highlight it.
String connectRouteFor(AskSource s) =>
    '/settings/connectors?connector=${s.connectorId ?? ''}';

/// "Looking through your calendar and files…" while a search runs.
String searchingLabelFor(Iterable<AskSource> sources) {
  final names = [
    for (final s in AskSource.values)
      if (sources.contains(s) && s != AskSource.docs) s.label.toLowerCase(),
  ];
  if (names.isEmpty) return 'Looking through your data…';
  final list = names.length == 1
      ? names.single
      : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  return 'Looking through your $list…';
}

// ---- the grounded prompt ---------------------------------------------------

/// Trusted instruction placed BEFORE the sources block.
const askInstruction =
    'Answer the question using only the sources below. Cite what you use '
    'like [1]. If the answer is not in the sources, say so plainly; do not '
    'guess or use outside knowledge.';

/// Used instead of [askInstruction] when document excerpts ride along.
const askInstructionWithDocs =
    'Answer the question using only the sources and document excerpts below. '
    'Cite sources like [1] and document pages like [p.3]. If the answer is '
    'not in them, say so plainly; do not guess or use outside knowledge.';

/// The user turn that replaces the plain question when sources are searched.
/// [docPrompt] (the doc-chat grounded prompt) rides along when documents are
/// also in play. A block with no items still goes out, so the model says
/// plainly that nothing matched instead of guessing.
String buildSourcedPrompt({
  required String question,
  required SourcesBlock block,
  required DateTime now,
  String? docExcerpts,
}) {
  final b = StringBuffer()
    ..writeln(docExcerpts == null ? askInstruction : askInstructionWithDocs)
    ..writeln('Today is ${shortDate(now)} ${now.year}, ${shortTime(now)}.')
    ..writeln()
    ..writeln(block.text);
  if (block.isEmpty) b.writeln('No items matched this question.');
  if (docExcerpts != null) {
    b
      ..writeln()
      ..writeln(docExcerpts);
  }
  b
    ..writeln()
    ..writeln('Question: ${question.trim()}')
    ..write('Answer:');
  return b.toString();
}

// ---- source chips under the answer -----------------------------------------

/// One citation chip under a grounded answer. Persisted in
/// `Messages.sourcesJson` next to document citations (told apart by `k`).
final class ItemSource {
  final int itemId;
  final String source;
  final ItemKind kind;

  /// Short chip text: "Ravi, Q4 budget" / "Mon 2 Nov, Design sync" / a file
  /// name.
  final String label;
  const ItemSource({
    required this.itemId,
    required this.source,
    required this.kind,
    required this.label,
  });

  Map<String, Object> toJson() => {
    'k': 'item',
    'id': itemId,
    'src': source,
    'kind': kind.name,
    'label': label,
  };

  static ItemSource? tryFromJson(Object? json) {
    if (json is! Map || json['k'] != 'item') return null;
    final id = json['id'];
    final src = json['src'];
    final kind = json['kind'];
    final label = json['label'];
    if (id is! int || src is! String || kind is! String || label is! String) {
      return null;
    }
    final k = ItemKind.values.where((v) => v.name == kind).firstOrNull;
    if (k == null) return null;
    return ItemSource(itemId: id, source: src, kind: k, label: label);
  }

  @override
  bool operator ==(Object other) =>
      other is ItemSource &&
      other.itemId == itemId &&
      other.source == source &&
      other.kind == kind &&
      other.label == label;

  @override
  int get hashCode => Object.hash(itemId, source, kind, label);
}

String _personName(Person p) {
  final n = p.name?.trim();
  if (n != null && n.isNotEmpty) return n.split(RegExp(r'\s+')).first;
  final e = p.email?.trim() ?? '';
  return e.contains('@') ? e.split('@').first : e;
}

/// The chip for [item].
ItemSource itemSourceFor(ConnectorItem item) {
  final title = item.title.trim();
  final String label;
  switch (item.kind) {
    case ItemKind.mail:
      final from = item.people.isEmpty ? '' : _personName(item.people.first);
      label = [from, title].where((s) => s.isNotEmpty).join(', ');
    case ItemKind.event:
      final when = item.startsAt;
      label = [
        if (when != null) shortDate(when),
        title,
      ].where((s) => s.isNotEmpty).join(', ');
    case ItemKind.contact:
      label = title;
    case ItemKind.file:
      final page = item.flags['pages'] != null ? item.flags['page'] : null;
      label = page is int ? '$title p.$page' : title;
    case ItemKind.notification:
      final app = item.flags['app'];
      label = [
        if (app is String && app.isNotEmpty && app != title) app,
        title,
      ].where((s) => s.isNotEmpty).join(', ');
  }
  return ItemSource(
    itemId: item.id,
    source: item.source,
    kind: item.kind,
    label: label.isEmpty ? item.kind.name : label,
  );
}

final _citation = RegExp(r'\[\s*(\d+(?:\s*[,;]\s*\d+)*)\s*\]');

/// The numbers the answer cites as `[1]`, `[2, 3]`.
Set<int> citedNumbers(String answer) {
  final out = <int>{};
  for (final m in _citation.allMatches(answer)) {
    for (final d in RegExp(r'\d+').allMatches(m.group(1)!)) {
      final n = int.tryParse(d.group(0)!);
      if (n != null) out.add(n);
    }
  }
  return out;
}

/// How many retrieved items still show as chips when the answer cites none
/// (small models forget markers): what was read, so the user can check.
const uncitedFallbackChips = 3;

/// Maps `[n]` markers back to the items the model was shown ([retrieved]
/// index + 1 = n, exactly [SourcesBlock.items]). Out-of-range numbers are
/// dropped; two sections of one file make one chip. No valid marker: the top
/// [uncitedFallbackChips] retrieved items.
List<ItemSource> citedItemSources(
  String answer,
  List<ConnectorItem> retrieved,
) {
  if (retrieved.isEmpty) return const [];
  final cited = citedNumbers(answer);
  final picked = [
    for (var i = 0; i < retrieved.length; i++)
      if (cited.contains(i + 1)) retrieved[i],
  ];
  final items = picked.isEmpty
      ? retrieved.take(uncitedFallbackChips).toList()
      : picked;
  final seen = <String>{};
  final out = <ItemSource>[];
  for (final item in items) {
    final s = itemSourceFor(item);
    if (seen.add('${s.source}|${s.kind.name}|${s.label}')) out.add(s);
  }
  return out;
}

// ---- persistence (shared column with document citations) -------------------

/// Encodes document + item citations for `Messages.sourcesJson`. Document
/// entries keep their original shape, so older builds still read them.
String encodeAnswerSources(
  List<Map<String, Object>> docJson,
  List<ItemSource> items,
) => jsonEncode([...docJson, for (final i in items) i.toJson()]);

/// Item citations stored in `Messages.sourcesJson`; garbage yields none.
List<ItemSource> decodeItemSources(String? json) {
  if (json == null || json.isEmpty) return const [];
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    return [for (final e in decoded) ?ItemSource.tryFromJson(e)];
  } on FormatException {
    return const [];
  }
}
