/// Which voice models are installed on disk (Loop 6, T2) — the composer's
/// hold-to-talk button, the hands-free entry point, and the per-message TTS
/// button all gate on this before touching [VoiceService]/`MicSource`, so
/// "no model installed" degrades to a CTA into the models hub's Voice tab
/// instead of a native load failure surfacing mid-recording.
///
/// A `FutureProvider` re-evaluated on every watch (Riverpod doesn't have a
/// filesystem watcher to invalidate on) — cheap (a handful of
/// `File.existsSync()` calls via `VoiceModelInstaller.isInstalled`), and
/// every screen that reads it also calls `ref.invalidate` after a voice
/// model finishes installing (`models_hub`'s Voice tab) or the user returns
/// from it (chat/hands-free screens invalidate `onResume`-equivalent spots —
/// see `HandsFreeScreen`/`Composer`'s `didPopNext`-style refresh).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../voice/voice_model_catalog.dart';
import 'default_voice.dart';

final class VoiceReadiness {
  final bool vadInstalled;
  final bool asrInstalled;
  final bool anyTtsInstalled;

  const VoiceReadiness({
    required this.vadInstalled,
    required this.asrInstalled,
    required this.anyTtsInstalled,
  });

  /// Hold-to-talk / hands-free listening both need VAD + ASR.
  bool get canListen => vadInstalled && asrInstalled;
}

final voiceReadinessProvider = FutureProvider<VoiceReadiness>((ref) async {
  final installer = await ref.watch(voiceModelInstallerProvider.future);
  final asrEntry = voiceModelCatalog.firstWhere(
    (e) => e.role == VoiceModelRole.asr,
  );
  final ttsEntries = voiceModelCatalog.where(
    (e) => e.role == VoiceModelRole.tts,
  );
  return VoiceReadiness(
    vadInstalled: installer.isInstalled(vadCatalogEntry),
    asrInstalled: installer.isInstalled(asrEntry),
    anyTtsInstalled: ttsEntries.any(installer.isInstalled),
  );
});

/// Whether the TTS voice [defaultVoiceEntryFor] would pick for [text] is
/// actually installed. Family-keyed by text so a message bubble can ask
/// "can I speak *this* reply" without the caller resolving the entry itself.
final ttsReadyForTextProvider = FutureProvider.family<bool, String>((
  ref,
  text,
) async {
  final entry = defaultVoiceEntryFor(text);
  if (entry == null) return false;
  final installer = await ref.watch(voiceModelInstallerProvider.future);
  return installer.isInstalled(entry);
});
