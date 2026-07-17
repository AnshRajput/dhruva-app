/// Import/export of the community "CharacterCard V2" format (`chara_card_v2`
/// — the JSON schema TavernAI/SillyTavern and the chub.ai/character-hub
/// ecosystem share) as both plain JSON and a PNG-embedded `tEXt`/`iTXt`
/// `chara` chunk (see `png_text_chunk.dart`).
///
/// ## Field mapping (card <-> our `CharacterInfo`, see
/// `character_repository.dart`)
///
/// | Our field             | Export (`data.*`)                    | Import composition |
/// |------------------------|----------------------------------------|---------------------|
/// | `name`                 | `name`                                  | `name` (required)  |
/// | `personaSystemPrompt`  | `system_prompt` (whole persona)        | `system_prompt` if `description`/`personality`/`scenario` are all empty (true for our own exports below); otherwise `system_prompt` + `"Description: "/"Personality: "/"Scenario: "` sections composed from those three fields — see [composePersonaSystemPrompt]. |
/// | `greeting`              | `first_mes`                            | `first_mes` |
/// | `exampleDialogues`      | `mes_example` (blocks joined by `<START>`) | split on `<START>` |
/// | `avatarEmoji`           | `extensions.dhruva.avatarEmoji`        | `extensions.dhruva.avatarEmoji` |
/// | `samplingParams`        | `extensions.dhruva.samplingParams`     | `extensions.dhruva.samplingParams` |
/// | `avatarPath`, `defaultModelId`, `isBuiltIn`, `id`/timestamps | not exported | not restored |
///
/// `description`/`personality`/`scenario` are always exported empty and the
/// full composed persona goes into `system_prompt` — we don't retain the
/// original three-way split, so re-exporting is lossy in that direction
/// but *importing our own export back* is lossless (nothing to compose
/// from, `system_prompt` is used verbatim), which is the round-trip
/// property that actually matters (see the test suite). `avatarPath` and
/// `defaultModelId` are local-device bookkeeping (a filesystem path / an
/// `InstalledModels` row id on THIS device) — meaningless on a different
/// device/install, so they're deliberately not part of the portable card.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../core/failures/app_failure.dart';
import '../chat/models/sampling_params.dart';
import 'png_text_chunk.dart';

const _pngCharaKeyword = 'chara';
const _exampleDialogueSeparator = '<START>';
const _dhruvaExtensionKey = 'dhruva';

/// A parsed/about-to-be-serialized `chara_card_v2` document. Only the
/// fields this codebase's mapping touches are modeled — unknown top-level
/// `data` keys are silently dropped on import (nothing here claims to be a
/// full-fidelity CharacterCard V2 editor).
final class CharacterCardV2 {
  final String name;
  final String description;
  final String personality;
  final String scenario;
  final String firstMes;
  final String mesExample;
  final String systemPrompt;
  final String creatorNotes;
  final Map<String, dynamic> extensions;

  const CharacterCardV2({
    required this.name,
    this.description = '',
    this.personality = '',
    this.scenario = '',
    this.firstMes = '',
    this.mesExample = '',
    this.systemPrompt = '',
    this.creatorNotes = '',
    this.extensions = const {},
  });

  /// Parses a decoded `chara_card_v2` JSON object (top-level `spec`/`data`).
  /// Throws [ValidationFailure] — never crashes — if [json] doesn't have a
  /// `data` object or a non-empty `data.name`. `spec`/`spec_version` values
  /// are read loosely (not hard-asserted) since real-world cards vary here.
  factory CharacterCardV2.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    if (data is! Map) {
      throw const ValidationFailure(
        'character card JSON has no "data" object (not a chara_card_v2 file)',
      );
    }
    final map = Map<String, dynamic>.from(data);
    String str(String key) => map[key] is String ? map[key] as String : '';
    final name = str('name');
    if (name.trim().isEmpty) {
      throw const ValidationFailure(
        'character card "data.name" is missing or empty',
      );
    }
    final rawExtensions = map['extensions'];
    return CharacterCardV2(
      name: name,
      description: str('description'),
      personality: str('personality'),
      scenario: str('scenario'),
      firstMes: str('first_mes'),
      mesExample: str('mes_example'),
      systemPrompt: str('system_prompt'),
      creatorNotes: str('creator_notes'),
      extensions: rawExtensions is Map
          ? Map<String, dynamic>.from(rawExtensions)
          : const {},
    );
  }

  /// Parses a raw JSON string. Throws [ValidationFailure] on invalid JSON
  /// or a JSON root that isn't an object (in addition to
  /// [CharacterCardV2.fromJson]'s own validation).
  factory CharacterCardV2.parse(String jsonStr) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonStr);
    } on FormatException catch (e) {
      throw ValidationFailure('character card is not valid JSON: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ValidationFailure(
        'character card JSON root is not an object',
      );
    }
    return CharacterCardV2.fromJson(decoded);
  }

  Map<String, dynamic> toJson() => {
    'spec': 'chara_card_v2',
    'spec_version': '2.0',
    'data': {
      'name': name,
      'description': description,
      'personality': personality,
      'scenario': scenario,
      'first_mes': firstMes,
      'mes_example': mesExample,
      'system_prompt': systemPrompt,
      'creator_notes': creatorNotes,
      'extensions': extensions,
    },
  };
}

/// The subset of `CharacterInfo`'s fields a card import produces — the
/// caller (`CharacterRepository.importCard`) fills in the rest (id,
/// timestamps, `isBuiltIn: false`, `avatarPath`/`defaultModelId` left null).
final class ImportedCharacterFields {
  final String name;
  final String personaSystemPrompt;
  final String? greeting;
  final List<String> exampleDialogues;
  final String? avatarEmoji;
  final SamplingParams? samplingParams;

  const ImportedCharacterFields({
    required this.name,
    required this.personaSystemPrompt,
    this.greeting,
    this.exampleDialogues = const [],
    this.avatarEmoji,
    this.samplingParams,
  });
}

/// Composes a persona system prompt from a card's `system_prompt` +
/// `description`/`personality`/`scenario`. If the latter three are all
/// blank, `systemPrompt` is returned verbatim — the case for cards this
/// codebase itself exported (see the file doc's mapping table), making
/// export -> import a lossless round trip for `personaSystemPrompt`.
String composePersonaSystemPrompt({
  required String systemPrompt,
  required String description,
  required String personality,
  required String scenario,
}) {
  final sp = systemPrompt.trim();
  final d = description.trim();
  final p = personality.trim();
  final s = scenario.trim();
  if (d.isEmpty && p.isEmpty && s.isEmpty) return sp;
  return [
    if (sp.isNotEmpty) sp,
    if (d.isNotEmpty) 'Description: $d',
    if (p.isNotEmpty) 'Personality: $p',
    if (s.isNotEmpty) 'Scenario: $s',
  ].join('\n\n');
}

List<String> _splitMesExample(String raw) {
  if (raw.trim().isEmpty) return const [];
  return raw
      .split(_exampleDialogueSeparator)
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
}

String _joinMesExample(List<String> dialogues) =>
    dialogues.map((d) => '$_exampleDialogueSeparator\n$d').join('\n');

/// Maps a parsed [card] to the fields needed to create a new `Character`
/// row. Throws [ValidationFailure] if the card has no usable persona
/// content at all (name is already validated by [CharacterCardV2.fromJson]/
/// `.parse`).
ImportedCharacterFields cardToCharacterFields(CharacterCardV2 card) {
  final persona = composePersonaSystemPrompt(
    systemPrompt: card.systemPrompt,
    description: card.description,
    personality: card.personality,
    scenario: card.scenario,
  );
  if (persona.isEmpty) {
    throw const ValidationFailure(
      'character card has no persona content '
      '(system_prompt/description/personality/scenario are all empty)',
    );
  }
  final dhruvaExt = card.extensions[_dhruvaExtensionKey];
  String? avatarEmoji;
  SamplingParams? samplingParams;
  if (dhruvaExt is Map) {
    final emoji = dhruvaExt['avatarEmoji'];
    if (emoji is String) avatarEmoji = emoji;
    final sampling = dhruvaExt['samplingParams'];
    if (sampling is Map) {
      samplingParams = SamplingParams.fromJson(
        Map<String, dynamic>.from(sampling),
      );
    }
  }
  return ImportedCharacterFields(
    name: card.name.trim(),
    personaSystemPrompt: persona,
    greeting: card.firstMes.trim().isEmpty ? null : card.firstMes.trim(),
    exampleDialogues: _splitMesExample(card.mesExample),
    avatarEmoji: avatarEmoji,
    samplingParams: samplingParams,
  );
}

/// Builds an exportable card from our own data. See the file doc's mapping
/// table for why `description`/`personality`/`scenario` are left empty
/// (the whole persona goes into `system_prompt`) and why `avatarEmoji`/
/// `samplingParams` ride along in `extensions.dhruva` rather than being
/// lost — both round-trip through our own import path above.
CharacterCardV2 characterToCard({
  required String name,
  required String personaSystemPrompt,
  String? greeting,
  List<String> exampleDialogues = const [],
  String? avatarEmoji,
  SamplingParams? samplingParams,
}) {
  return CharacterCardV2(
    name: name,
    systemPrompt: personaSystemPrompt,
    firstMes: greeting ?? '',
    mesExample: _joinMesExample(exampleDialogues),
    extensions: {
      _dhruvaExtensionKey: {
        'avatarEmoji': ?avatarEmoji,
        'samplingParams': ?samplingParams?.toJson(),
      },
    },
  );
}

// ---- PNG embedding ---------------------------------------------------

/// Embeds [cardJson] (typically `CharacterCardV2.toJson()`) as a base64
/// `tEXt` chunk keyed `chara` — the same convention SillyTavern-style
/// tooling uses — into [avatarPng], or a generated placeholder if none is
/// supplied.
Uint8List embedCardInPng(
  Map<String, dynamic> cardJson, {
  Uint8List? avatarPng,
}) {
  final png = avatarPng ?? placeholderPng;
  final base64Card = base64Encode(utf8.encode(jsonEncode(cardJson)));
  return embedTextChunk(png, _pngCharaKeyword, base64Card);
}

/// Extracts and decodes the `chara` card JSON embedded in [png]. Throws
/// [ValidationFailure] — never crashes — if [png] isn't a valid PNG, has no
/// `chara` chunk, or the payload isn't valid base64/JSON.
Map<String, dynamic> extractCardFromPng(Uint8List png) {
  String? base64Card;
  try {
    base64Card = readTextChunk(png, _pngCharaKeyword);
  } on FormatException catch (e) {
    throw ValidationFailure('not a valid PNG: ${e.message}');
  }
  if (base64Card == null) {
    throw const ValidationFailure('PNG has no embedded "chara" card data');
  }
  try {
    final decoded = jsonDecode(utf8.decode(base64Decode(base64Card.trim())));
    if (decoded is! Map<String, dynamic>) {
      throw const ValidationFailure(
        'embedded card payload is not a JSON object',
      );
    }
    return decoded;
  } on ValidationFailure {
    rethrow;
  } catch (e) {
    throw ValidationFailure(
      'embedded card payload is not valid base64/JSON: $e',
    );
  }
}
