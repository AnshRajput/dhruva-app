/// Picks a TTS voice for a piece of assistant text (Loop 6, T2).
///
/// GAP (flagged per the Loop-6 build brief): `CharacterInfo`
/// (`data/characters/character_repository.dart`) has no `voiceId` field, so
/// there is no way to bind "this character always speaks in voice X" the way
/// `defaultModelId`/`samplingParams` already bind a default model/sampling
/// per character. Absent that field, the only signal this loop has to pick
/// between the catalog's two TTS voices is the language of the text actually
/// being spoken — which is what [defaultVoiceEntryFor] does. A character's
/// *existence* (whether a conversation is character-bound at all) carries no
/// extra information without a stored voice preference, so it isn't used
/// here. Adding `Characters.voiceId` (nullable, `Characters` table
/// migration) and threading it through `CharacterChatContext` is the
/// straightforward follow-up once that field exists — this function's
/// language fallback would remain the correct behavior for characters that
/// haven't picked one.
library;

import '../../../voice/voice_model_catalog.dart';

/// Unicode range for the Devanagari script (Hindi, and Hinglish written in
/// Devanagari) — cheap, dependency-free "is this Hindi text" signal. Text
/// that's Hinglish-in-Latin-script (very common in practice) has no reliable
/// signal here and falls back to the English voice, which is the safer
/// mispronunciation direction (an English voice reading transliterated Hindi
/// reads as accented-but-intelligible; a Hindi voice reading English text
/// reads as broken).
final _devanagari = RegExp(r'[ऀ-ॿ]');

/// The TTS entry to synthesize [text] with: the Hindi voice if [text]
/// contains Devanagari script, the English voice otherwise.
///
/// When [isInstalled] is given, the choice is constrained to voices that
/// actually pass it: the language-matched voice is preferred, but if it isn't
/// installed we fall back to ANY installed voice rather than dead-ending on a
/// voice that can't speak. This is what keeps a Hindi reply audible when only
/// the English voice is on disk (and vice-versa) — an accented-but-audible
/// reply beats a silent, text-only one (the one-tap bundle only ships the
/// English voice, yet Whisper auto-detects Hindi). Returns null only when no
/// TTS voice at all is available, which the caller treats as "not installed".
VoiceCatalogEntry? defaultVoiceEntryFor(
  String text, {
  bool Function(VoiceCatalogEntry entry)? isInstalled,
}) {
  final language = _devanagari.hasMatch(text) ? 'hi' : 'en';
  final voices = voiceModelCatalog.where(
    (e) => e.role == VoiceModelRole.tts && (isInstalled?.call(e) ?? true),
  );
  return voices.where((e) => e.languages.contains(language)).firstOrNull ??
      voices.firstOrNull;
}
