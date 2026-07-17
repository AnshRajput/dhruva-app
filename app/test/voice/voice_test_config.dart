// Shared resolver for the REAL sherpa_onnx voice test. Not a `*_test.dart`
// file, so `flutter test` doesn't run it directly.
//
// The real round-trip only runs when: this is macOS, the sherpa native dylib is
// present + loadable, and the dev voice models are extracted under
// `.dev-native/voice-models/`. Otherwise it returns null and the test skips —
// keeping `make verify` / Linux CI green (they have neither the dylib nor the
// models). Paths come from env vars first, then fall back to this machine's
// layout, mirroring `native_test_config.dart`.
//
// One macOS wrinkle: the dylib sherpa ships in the pub cache has an INVALID
// arm64 code signature, so macOS SIGKILLs the process on load. We ad-hoc
// re-sign it in place (best-effort) so the test is self-healing after a fresh
// `flutter pub get`.

import 'dart:convert';
import 'dart:io';

import 'package:dhruva/voice/voice_service.dart';
import 'package:path/path.dart' as p;

class VoiceTestPaths {
  final String libraryDirectory;
  final AsrModelConfig asr;
  final TtsModelConfig tts;
  final VadConfig vad;
  const VoiceTestPaths({
    required this.libraryDirectory,
    required this.asr,
    required this.tts,
    required this.vad,
  });
}

/// Resolve everything the real test needs, or null to skip.
VoiceTestPaths? resolveVoiceTestPaths() {
  if (!Platform.isMacOS) return null;

  final libDir =
      Platform.environment['DHRUVA_SHERPA_LIB_DIR'] ?? _pubCacheMacosDir();
  if (libDir == null) return null;
  if (!_ensureLoadable(libDir)) return null;

  final modelsRoot =
      Platform.environment['DHRUVA_VOICE_MODELS'] ??
      p.join(Directory.current.path, '.dev-native', 'voice-models');

  final whisper = p.join(modelsRoot, 'sherpa-onnx-whisper-tiny');
  final amy = p.join(modelsRoot, 'vits-piper-en_US-amy-low');
  final vad = p.join(modelsRoot, 'silero_vad.onnx');

  final encoder = p.join(whisper, 'tiny-encoder.int8.onnx');
  final decoder = p.join(whisper, 'tiny-decoder.int8.onnx');
  final tokens = p.join(whisper, 'tiny-tokens.txt');
  final ttsModel = p.join(amy, 'en_US-amy-low.onnx');
  final ttsTokens = p.join(amy, 'tokens.txt');
  final dataDir = p.join(amy, 'espeak-ng-data');

  for (final f in [encoder, decoder, tokens, ttsModel, ttsTokens, vad]) {
    if (!File(f).existsSync()) return null;
  }
  if (!Directory(dataDir).existsSync()) return null;

  return VoiceTestPaths(
    libraryDirectory: libDir,
    asr: AsrModelConfig(
      type: AsrModelType.whisper,
      encoder: encoder,
      decoder: decoder,
      tokens: tokens,
    ),
    tts: TtsModelConfig(
      type: TtsModelType.vits,
      model: ttsModel,
      tokens: ttsTokens,
      dataDir: dataDir,
    ),
    vad: VadConfig(model: vad),
  );
}

/// Find `sherpa_onnx_macos/macos` from the resolved package config (version-
/// agnostic), returning null if the package isn't resolved.
String? _pubCacheMacosDir() {
  final cfg = File(
    p.join(Directory.current.path, '.dart_tool', 'package_config.json'),
  );
  if (!cfg.existsSync()) return null;
  final json = jsonDecode(cfg.readAsStringSync()) as Map<String, dynamic>;
  final packages = (json['packages'] as List).cast<Map<String, dynamic>>();
  final pkg = packages.firstWhere(
    (e) => e['name'] == 'sherpa_onnx_macos',
    orElse: () => const {},
  );
  final rootUri = pkg['rootUri'] as String?;
  if (rootUri == null) return null;
  final root = rootUri.startsWith('file://')
      ? Uri.parse(rootUri).toFilePath()
      : p.normalize(p.join(cfg.parent.path, rootUri));
  final dir = p.join(root, 'macos');
  return Directory(dir).existsSync() ? dir : null;
}

/// True if the dylib in [dir] is code-sign-valid (loadable). If not, ad-hoc
/// re-sign every dylib there and re-check. A hard SIGKILL on load can't be
/// caught, so we must gate on the signature *before* loading.
bool _ensureLoadable(String dir) {
  final dylib = p.join(dir, 'libsherpa-onnx-c-api.dylib');
  if (!File(dylib).existsSync()) return false;
  if (_codesignValid(dylib)) return true;
  for (final f in Directory(dir).listSync().whereType<File>()) {
    if (f.path.endsWith('.dylib')) {
      Process.runSync('codesign', ['-f', '-s', '-', f.path]);
    }
  }
  return _codesignValid(dylib);
}

bool _codesignValid(String path) {
  final r = Process.runSync('codesign', ['--verify', path]);
  return r.exitCode == 0;
}
