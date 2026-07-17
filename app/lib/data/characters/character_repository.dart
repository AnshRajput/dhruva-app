import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/failures/app_failure.dart';
import '../chat/models/sampling_params.dart';
import '../db/database.dart';
import 'character_card.dart';
import 'character_seed.dart';

/// One `Characters` row, surfaced without the drift-generated type — same
/// precedent as `ConversationSummary`/`MessageInfo` (ADR-002: `features/`
/// never imports drift directly).
final class CharacterInfo {
  final int id;
  final String name;
  final String? avatarEmoji;
  final String? avatarPath;
  final String personaSystemPrompt;
  final String? greeting;
  final List<String> exampleDialogues;
  final int? defaultModelId;

  /// Null means "no character-level override" — see `Characters.
  /// samplingParamsJson`'s doc.
  final SamplingParams? samplingParams;
  final bool isBuiltIn;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CharacterInfo({
    required this.id,
    required this.name,
    this.avatarEmoji,
    this.avatarPath,
    required this.personaSystemPrompt,
    this.greeting,
    this.exampleDialogues = const [],
    this.defaultModelId,
    this.samplingParams,
    required this.isBuiltIn,
    required this.createdAt,
    required this.updatedAt,
  });
}

/// Everything `features/chat` needs to start (or continue) a conversation
/// with a character: the persona as a system prompt, an optional greeting
/// to seed the thread with, and the character's default model/sampling
/// overrides. Both `defaultModelId` and `samplingParams` are nullable —
/// null means "no override; the caller's own default applies" (the same
/// convention `Characters.samplingParamsJson` itself uses).
///
/// Deliberately plain data: this file never imports `engine_bindings` or
/// anything under `features/` (ADR-002 — `data/` doesn't reach into
/// `features/`), so `features/chat` builds its own
/// `ChatTurn.system(context.systemPrompt)`/model-load call from these
/// fields rather than this layer committing to the engine's types.
final class CharacterChatContext {
  final String systemPrompt;
  final String? greeting;
  final int? defaultModelId;
  final SamplingParams? samplingParams;

  const CharacterChatContext({
    required this.systemPrompt,
    this.greeting,
    this.defaultModelId,
    this.samplingParams,
  });
}

/// CRUD + built-in seeding + community-card import/export over the Loop-5
/// `Characters` table (`data/db/database.dart`).
///
/// Built-in dedup: the starter pack has no stable id column to upsert
/// against (`Characters` doesn't carry the seed asset's `"id"` slug — see
/// `character_seed.dart`), so [seedBuiltInsIfPresent] matches existing rows
/// by `(isBuiltIn: true, name)`. Ten curated, distinctly-named starter
/// characters make that safe in practice; a user is free to name their own
/// character the same as a built-in without colliding, since theirs has
/// `isBuiltIn: false`.
final class CharacterRepository {
  final AppDatabase _db;
  final Future<String?> Function() _loadStarterPack;

  CharacterRepository({
    required AppDatabase db,
    Future<String?> Function()? starterPackLoader,
  }) : _db = db,
       _loadStarterPack = starterPackLoader ?? _defaultStarterPackLoader;

  static Future<String?> _defaultStarterPackLoader() async {
    try {
      return await rootBundle.loadString('assets/characters/starter_pack.json');
    } catch (_) {
      // Tolerate the asset being entirely absent (undeclared in pubspec, or
      // missing from this checkout) — seeding is a no-op, not a crash.
      return null;
    }
  }

  // ---- CRUD ---------------------------------------------------------

  Future<int> createCharacter({
    required String name,
    String? avatarEmoji,
    String? avatarPath,
    required String personaSystemPrompt,
    String? greeting,
    List<String> exampleDialogues = const [],
    int? defaultModelId,
    SamplingParams? samplingParams,
    bool isBuiltIn = false,
  }) {
    samplingParams?.validate();
    final now = DateTime.now();
    return _db
        .into(_db.characters)
        .insert(
          CharactersCompanion.insert(
            name: name,
            avatarEmoji: Value(avatarEmoji),
            avatarPath: Value(avatarPath),
            personaSystemPrompt: personaSystemPrompt,
            greeting: Value(greeting),
            exampleDialogues: Value(_encodeDialogues(exampleDialogues)),
            defaultModelId: Value(defaultModelId),
            samplingParamsJson: Value(_encodeSampling(samplingParams)),
            isBuiltIn: Value(isBuiltIn),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  /// Replaces every editable field of character [id] (an edit form submits
  /// the whole record, not a sparse patch — see `features/characters`'
  /// planned create/edit form). `isBuiltIn` is never changed by this method.
  Future<void> updateCharacter({
    required int id,
    required String name,
    String? avatarEmoji,
    String? avatarPath,
    required String personaSystemPrompt,
    String? greeting,
    List<String> exampleDialogues = const [],
    int? defaultModelId,
    SamplingParams? samplingParams,
  }) async {
    samplingParams?.validate();
    final updated =
        await (_db.update(_db.characters)..where((t) => t.id.equals(id))).write(
          CharactersCompanion(
            name: Value(name),
            avatarEmoji: Value(avatarEmoji),
            avatarPath: Value(avatarPath),
            personaSystemPrompt: Value(personaSystemPrompt),
            greeting: Value(greeting),
            exampleDialogues: Value(_encodeDialogues(exampleDialogues)),
            defaultModelId: Value(defaultModelId),
            samplingParamsJson: Value(_encodeSampling(samplingParams)),
            updatedAt: Value(DateTime.now()),
          ),
        );
    if (updated == 0) {
      throw StorageNotFoundFailure('no character with id $id');
    }
  }

  Future<void> deleteCharacter(int id) async {
    final deleted = await (_db.delete(
      _db.characters,
    )..where((t) => t.id.equals(id))).go();
    if (deleted == 0) {
      throw StorageNotFoundFailure('no character with id $id');
    }
  }

  Future<CharacterInfo?> getCharacter(int id) async {
    final row = await (_db.select(
      _db.characters,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toInfo(row);
  }

  /// Built-ins first (then alphabetical), user characters after (then
  /// alphabetical) — pass [builtInsFirst]: false for a flat alphabetical
  /// list instead.
  Future<List<CharacterInfo>> listCharacters({
    bool builtInsFirst = true,
  }) async {
    final query = _db.select(_db.characters);
    query.orderBy([
      if (builtInsFirst) (t) => OrderingTerm.desc(t.isBuiltIn),
      (t) => OrderingTerm.asc(t.name),
    ]);
    final rows = await query.get();
    return rows.map(_toInfo).toList(growable: false);
  }

  // ---- Chat integration ----------------------------------------------

  /// The pure mapping `features/chat` calls to turn a character into what
  /// it needs to start/continue a thread. Returns null if [characterId]
  /// doesn't exist (e.g. deleted — callers should treat that like "no
  /// character", not an error, since `Conversations.characterId` already
  /// tolerates this via `ON DELETE SET NULL`).
  Future<CharacterChatContext?> chatContextFor(int characterId) async {
    final character = await getCharacter(characterId);
    if (character == null) return null;
    return CharacterChatContext(
      systemPrompt: character.personaSystemPrompt,
      greeting: character.greeting,
      defaultModelId: character.defaultModelId,
      samplingParams: character.samplingParams,
    );
  }

  // ---- Card interop ----------------------------------------------------

  /// Imports a parsed community card as a new (non-built-in) character.
  /// Returns the new row's id.
  Future<int> importCard(CharacterCardV2 card) {
    final fields = cardToCharacterFields(card);
    return createCharacter(
      name: fields.name,
      avatarEmoji: fields.avatarEmoji,
      personaSystemPrompt: fields.personaSystemPrompt,
      greeting: fields.greeting,
      exampleDialogues: fields.exampleDialogues,
      samplingParams: fields.samplingParams,
    );
  }

  /// Parses [jsonStr] as a `chara_card_v2` document and imports it. Throws
  /// [ValidationFailure] on malformed input (see [CharacterCardV2.parse]).
  Future<int> importCardJson(String jsonStr) =>
      importCard(CharacterCardV2.parse(jsonStr));

  /// Extracts the `chara` PNG chunk from [pngBytes] and imports it. Throws
  /// [ValidationFailure] on a malformed PNG or card (see
  /// `extractCardFromPng`).
  Future<int> importCardFromPng(Uint8List pngBytes) =>
      importCard(CharacterCardV2.fromJson(extractCardFromPng(pngBytes)));

  Future<String> exportCardJson(int characterId) async {
    final character = await _requireCharacter(characterId);
    return jsonEncode(_toCard(character).toJson());
  }

  /// Embeds character [characterId]'s card into [avatarPng] (or a
  /// generated placeholder if omitted) and returns the resulting PNG bytes.
  Future<Uint8List> exportCardPng(
    int characterId, {
    Uint8List? avatarPng,
  }) async {
    final character = await _requireCharacter(characterId);
    return embedCardInPng(_toCard(character).toJson(), avatarPng: avatarPng);
  }

  CharacterCardV2 _toCard(CharacterInfo c) => characterToCard(
    name: c.name,
    personaSystemPrompt: c.personaSystemPrompt,
    greeting: c.greeting,
    exampleDialogues: c.exampleDialogues,
    avatarEmoji: c.avatarEmoji,
    samplingParams: c.samplingParams,
  );

  Future<CharacterInfo> _requireCharacter(int id) async {
    final character = await getCharacter(id);
    if (character == null) {
      throw StorageNotFoundFailure('no character with id $id');
    }
    return character;
  }

  // ---- Built-in seeding -------------------------------------------------

  /// Idempotently upserts the starter pack from
  /// `assets/characters/starter_pack.json`, if present (see
  /// [_defaultStarterPackLoader] / the constructor's `starterPackLoader`
  /// override). Returns the number of built-in characters seeded/updated,
  /// or 0 if the asset is absent. Safe to call on every app start — an
  /// unchanged entry is a no-op write, a changed one (a future release
  /// editing a starter persona) updates in place rather than duplicating.
  Future<int> seedBuiltInsIfPresent() async {
    final raw = await _loadStarterPack();
    if (raw == null) return 0;
    final seeds = parseCharacterSeeds(raw);
    for (final seed in seeds) {
      await _upsertBuiltIn(seed);
    }
    return seeds.length;
  }

  Future<void> _upsertBuiltIn(CharacterSeedEntry seed) async {
    final existing =
        await (_db.select(_db.characters)..where(
              (t) => t.isBuiltIn.equals(true) & t.name.equals(seed.name),
            ))
            .getSingleOrNull();
    if (existing == null) {
      final now = DateTime.now();
      await _db
          .into(_db.characters)
          .insert(
            CharactersCompanion.insert(
              name: seed.name,
              avatarEmoji: Value(seed.avatarEmoji),
              personaSystemPrompt: seed.personaSystemPrompt,
              greeting: Value(seed.greeting),
              exampleDialogues: Value(_encodeDialogues(seed.exampleDialogues)),
              samplingParamsJson: Value(_encodeSampling(seed.samplingParams)),
              isBuiltIn: const Value(true),
              createdAt: now,
              updatedAt: now,
            ),
          );
    } else {
      await (_db.update(
        _db.characters,
      )..where((t) => t.id.equals(existing.id))).write(
        CharactersCompanion(
          avatarEmoji: Value(seed.avatarEmoji),
          personaSystemPrompt: Value(seed.personaSystemPrompt),
          greeting: Value(seed.greeting),
          exampleDialogues: Value(_encodeDialogues(seed.exampleDialogues)),
          samplingParamsJson: Value(_encodeSampling(seed.samplingParams)),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  // ---- shared helpers ----------------------------------------------------

  static String? _encodeDialogues(List<String> dialogues) =>
      dialogues.isEmpty ? null : jsonEncode(dialogues);

  static String? _encodeSampling(SamplingParams? params) =>
      params == null ? null : jsonEncode(params.toJson());

  CharacterInfo _toInfo(Character row) => CharacterInfo(
    id: row.id,
    name: row.name,
    avatarEmoji: row.avatarEmoji,
    avatarPath: row.avatarPath,
    personaSystemPrompt: row.personaSystemPrompt,
    greeting: row.greeting,
    exampleDialogues: row.exampleDialogues == null
        ? const []
        : (jsonDecode(row.exampleDialogues!) as List).cast<String>(),
    defaultModelId: row.defaultModelId,
    samplingParams: row.samplingParamsJson == null
        ? null
        : SamplingParams.fromJson(
            jsonDecode(row.samplingParamsJson!) as Map<String, dynamic>,
          ),
    isBuiltIn: row.isBuiltIn,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}
