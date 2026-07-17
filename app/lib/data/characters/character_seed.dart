import 'dart:convert';

import '../../core/failures/app_failure.dart';
import '../chat/models/sampling_params.dart';

/// One entry of the built-in "starter pack" character asset
/// (`assets/characters/starter_pack.json`). See
/// `CharacterRepository.seedBuiltInsIfPresent` for how this is consumed —
/// the asset is tolerated as absent (not every checkout/build ships it yet).
///
/// Real shipped shape (a top-level JSON array):
/// ```json
/// [
///   {
///     "id": "builtin/coach",
///     "name": "Coach",
///     "avatarEmoji": "💪",
///     "personaSystemPrompt": "You are Coach, ...",
///     "greeting": "Hey! I'm Coach. ...",
///     "exampleDialogues": [
///       {"user": "...", "assistant": "..."}
///     ],
///     "defaultSampling": {"temperature": 0.7, "topP": 0.9, "topK": 40}
///   }
/// ]
/// ```
/// `id` is a human-authoring slug, not persisted — [CharacterRepository]
/// dedupes built-ins by `name` (see its class doc). Only `name` and
/// `personaSystemPrompt` are required; everything else defaults to null/
/// empty. `exampleDialogues` entries are `{user, assistant}` pairs, folded
/// into `"User: ...\nAssistant: ..."` strings to match the flat
/// `List<String>` shape `Characters.exampleDialogues` and
/// `character_card.dart`'s `mes_example` mapping both use.
final class CharacterSeedEntry {
  final String name;
  final String? avatarEmoji;
  final String personaSystemPrompt;
  final String? greeting;
  final List<String> exampleDialogues;
  final SamplingParams? samplingParams;

  const CharacterSeedEntry({
    required this.name,
    this.avatarEmoji,
    required this.personaSystemPrompt,
    this.greeting,
    this.exampleDialogues = const [],
    this.samplingParams,
  });
}

/// Parses the starter-pack JSON. Throws [ValidationFailure] — never crashes
/// on malformed input — if [jsonStr] isn't a JSON array of objects, or an
/// entry is missing a required field.
List<CharacterSeedEntry> parseCharacterSeeds(String jsonStr) {
  final Object? decoded;
  try {
    decoded = jsonDecode(jsonStr);
  } on FormatException catch (e) {
    throw ValidationFailure('starter pack is not valid JSON: ${e.message}');
  }
  if (decoded is! List) {
    throw const ValidationFailure('starter pack JSON root is not an array');
  }
  return decoded.map(_parseEntry).toList(growable: false);
}

CharacterSeedEntry _parseEntry(dynamic entry) {
  if (entry is! Map) {
    throw const ValidationFailure('starter pack entry is not an object');
  }
  final map = Map<String, dynamic>.from(entry);
  final name = map['name'];
  if (name is! String || name.trim().isEmpty) {
    throw const ValidationFailure('starter pack entry is missing "name"');
  }
  final persona = map['personaSystemPrompt'];
  if (persona is! String || persona.trim().isEmpty) {
    throw ValidationFailure(
      'starter pack entry "$name" is missing "personaSystemPrompt"',
    );
  }
  return CharacterSeedEntry(
    name: name,
    avatarEmoji: map['avatarEmoji'] is String
        ? map['avatarEmoji'] as String
        : null,
    personaSystemPrompt: persona,
    greeting: map['greeting'] is String ? map['greeting'] as String : null,
    exampleDialogues: _parseExampleDialogues(map['exampleDialogues']),
    samplingParams: _parseSampling(map['defaultSampling']),
  );
}

List<String> _parseExampleDialogues(dynamic raw) {
  if (raw is! List) return const [];
  final out = <String>[];
  for (final entry in raw) {
    if (entry is String) {
      out.add(entry);
    } else if (entry is Map) {
      final user = entry['user'];
      final assistant = entry['assistant'];
      final lines = <String>[
        if (user is String && user.isNotEmpty) 'User: $user',
        if (assistant is String && assistant.isNotEmpty)
          'Assistant: $assistant',
      ];
      if (lines.isNotEmpty) out.add(lines.join('\n'));
    }
  }
  return out;
}

SamplingParams? _parseSampling(dynamic raw) {
  if (raw is! Map) return null;
  return SamplingParams.fromJson(Map<String, dynamic>.from(raw));
}
