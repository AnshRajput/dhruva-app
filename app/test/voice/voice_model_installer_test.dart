import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dhruva/voice/voice_model_catalog.dart';
import 'package:dhruva/voice/voice_model_installer.dart';
import 'package:dhruva/voice/voice_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Build a real `.tar.bz2` from [entries] (name → contents) at [path].
File _makeTarBz2(String path, Map<String, String> entries) {
  final archive = Archive();
  for (final e in entries.entries) {
    archive.addFile(ArchiveFile.string(e.key, e.value));
  }
  final tar = TarEncoder().encodeBytes(archive);
  final bz2 = BZip2Encoder().encodeBytes(tar);
  return File(path)..writeAsBytesSync(bz2);
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('voice_installer_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('extractTarBz2', () {
    test('extracts nested files with correct contents', () {
      final archive = _makeTarBz2(p.join(tmp.path, 'm.tar.bz2'), {
        'model/enc.onnx': 'ENCODER',
        'model/tokens.txt': 'TOKENS',
      });
      final dest = Directory(p.join(tmp.path, 'out'));
      final written = extractTarBz2(archive, dest);

      expect(written, containsAll(['model/enc.onnx', 'model/tokens.txt']));
      expect(
        File(p.join(dest.path, 'model', 'enc.onnx')).readAsStringSync(),
        'ENCODER',
      );
      expect(
        File(p.join(dest.path, 'model', 'tokens.txt')).readAsStringSync(),
        'TOKENS',
      );
    });

    test('rejects a zip-slip entry that escapes the install dir', () {
      final archive = _makeTarBz2(p.join(tmp.path, 'evil.tar.bz2'), {
        '../escape.txt': 'pwned',
      });
      final dest = Directory(p.join(tmp.path, 'out'));
      expect(
        () => extractTarBz2(archive, dest),
        throwsA(isA<VoiceModelLoadFailure>()),
      );
      expect(File(p.join(tmp.path, 'escape.txt')).existsSync(), isFalse);
    });
  });

  group('install (archive entry)', () {
    test('extracts the downloaded archive and deletes it', () async {
      final entry = voiceModelCatalog.firstWhere((e) => e.id == 'whisper-tiny');
      // Simulate DownloadManager having fetched the archive into modelsDir.
      _makeTarBz2(p.join(tmp.path, entry.archiveName), {
        'sherpa-onnx-whisper-tiny/tiny-encoder.int8.onnx': 'E',
        'sherpa-onnx-whisper-tiny/tiny-decoder.int8.onnx': 'D',
        'sherpa-onnx-whisper-tiny/tiny-tokens.txt': 'T',
      });
      final installer = VoiceModelInstaller(modelsDirectory: tmp);

      expect(installer.isInstalled(entry), isFalse);
      await installer.install(entry);

      expect(installer.isInstalled(entry), isTrue);
      // Archive reclaimed.
      expect(File(p.join(tmp.path, entry.archiveName)).existsSync(), isFalse);
      final asr = installer.asrConfig(entry, language: 'hi');
      expect(File(asr.encoder).existsSync(), isTrue);
      expect(asr.type, AsrModelType.whisper);
      expect(asr.language, 'hi');
    });

    test('throws if the archive was never downloaded', () {
      final entry = voiceModelCatalog.firstWhere((e) => e.id == 'whisper-tiny');
      final installer = VoiceModelInstaller(modelsDirectory: tmp);
      expect(installer.install(entry), throwsA(isA<VoiceModelLoadFailure>()));
    });
  });

  group('trust boundary: hostile/corrupt archives (Loop 6 QA)', () {
    test('BUG (QA loop 6, severity: medium): a real archive truncated '
        'mid-stream throws an UNTYPED exception (RangeError from the bzip2 '
        'decoder), not a VoiceFailure — VoiceModelsController._finishInstall '
        '(features/models_hub/state/voice_models_controller.dart) only '
        'catches `on VoiceFailure`, so this escapes as an unhandled async '
        'error and the Voice-tab tile is left stuck on "installing" forever '
        'instead of surfacing "failed" with a message. Root cause: '
        'extractTarBz2/install() never wrap BZip2Decoder/TarDecoder in a '
        'try/catch the way _loadAsr/_loadTts/_loadVad do in '
        'sherpa_voice_service.dart. NOT caught by the DownloadManager\'s own '
        'size check upstream: that only rejects a SHORT read (see the '
        'passing "downloadSizeBytes mismatch" path in '
        'voice_models_controller_test.dart) — a same-length, bit-corrupted '
        'transfer (no sha256 published for any voice-catalog entry, see '
        'voice_model_catalog.dart\'s own doc comment) sails through the size '
        'check and reaches this exact code path in production. '
        'This test currently FAILS (red) — that IS the filed bug; fix by '
        'wrapping the decode in try/catch -> VoiceModelLoadFailure, same '
        'shape as the sherpa worker\'s native-call wrapping.', () async {
      final tmp2 = Directory.systemTemp.createTempSync('voice_trunc_');
      addTearDown(() => tmp2.deleteSync(recursive: true));
      final entry = voiceModelCatalog.firstWhere((e) => e.id == 'whisper-tiny');
      // A real tar.bz2 (valid magic header, genuine compressed stream),
      // cut in half — not garbage bytes, which the decoder tolerates by
      // silently producing zero entries (caught downstream by _verify,
      // NOT the case being tested here).
      final full = _makeTarBz2(p.join(tmp2.path, '_full.tar.bz2'), {
        'sherpa-onnx-whisper-tiny/tiny-encoder.int8.onnx': 'E' * 5000,
        'sherpa-onnx-whisper-tiny/tiny-decoder.int8.onnx': 'D' * 5000,
        'sherpa-onnx-whisper-tiny/tiny-tokens.txt': 'T' * 5000,
      });
      final fullBytes = full.readAsBytesSync();
      File(
        p.join(tmp2.path, entry.archiveName),
      ).writeAsBytesSync(fullBytes.sublist(0, fullBytes.length ~/ 2));
      final installer = VoiceModelInstaller(modelsDirectory: tmp2);

      // Desired contract: any archive failure — corrupt, truncated, or
      // garbage — surfaces as a typed VoiceFailure so callers (the models
      // hub controller) can show "failed" instead of getting stuck.
      await expectLater(installer.install(entry), throwsA(isA<VoiceFailure>()));
    });

    test('garbage (non-bz2-magic) bytes decode to zero entries — caught by '
        'the post-extract _verify() as a typed VoiceModelLoadFailure (this '
        'path IS already handled correctly; the bug above is specifically '
        'about a real-but-truncated stream)', () async {
      final entry = voiceModelCatalog.firstWhere((e) => e.id == 'whisper-tiny');
      File(
        p.join(tmp.path, entry.archiveName),
      ).writeAsBytesSync(List.generate(500, (i) => i % 256));
      final installer = VoiceModelInstaller(modelsDirectory: tmp);
      await expectLater(
        installer.install(entry),
        throwsA(isA<VoiceModelLoadFailure>()),
      );
      expect(installer.isInstalled(entry), isFalse);
    });

    test('zip-slip: a malicious entry name is rejected and nothing lands '
        'outside destDir, even alongside otherwise-legitimate entries in the '
        'same archive', () {
      final archive = _makeTarBz2(p.join(tmp.path, 'evil2.tar.bz2'), {
        'sherpa-onnx-whisper-tiny/tiny-tokens.txt': 'legit',
        '../../../../etc/evil': 'pwned',
      });
      final dest = Directory(p.join(tmp.path, 'out2'));
      expect(
        () => extractTarBz2(archive, dest),
        throwsA(isA<VoiceModelLoadFailure>()),
      );
      // Nothing was left behind outside destDir from the poisoned entry —
      // whether or not the legit entry (which sorts first) was written
      // before the rejection, the escape target must not exist.
      expect(File(p.join(tmp.path, 'evil')).existsSync(), isFalse);
      expect(Directory(p.join(tmp.path, 'etc')).existsSync(), isFalse);
    });

    test('absolute-path entry is also rejected as zip-slip (not just relative '
        '..)', () {
      final archive = _makeTarBz2(p.join(tmp.path, 'evil3.tar.bz2'), {
        '/tmp/dhruva-evil-absolute': 'pwned',
      });
      final dest = Directory(p.join(tmp.path, 'out3'));
      expect(
        () => extractTarBz2(archive, dest),
        throwsA(isA<VoiceModelLoadFailure>()),
      );
    });

    test('high compression-ratio archive (bomb-shaped) still respects the '
        'zip-slip containment and completes without writing outside destDir '
        '— NOTE: true unbounded-size protection is a documented, accepted '
        'ponytail gap (voice_model_installer.dart\'s own doc comment: '
        '"whole-archive-in-memory bz2 decode... upgrade path: a streaming '
        'bz2 decoder if a much larger bundle ever ships"), not a new finding '
        '— this test only pins that containment holds regardless of ratio', () {
      // ~50:1-ish ratio via one highly-repetitive file — enough to prove
      // the point fast without actually stressing test-suite memory.
      final archive = _makeTarBz2(p.join(tmp.path, 'bomb.tar.bz2'), {
        'sherpa-onnx-whisper-tiny/tiny-tokens.txt': 'A' * 2000000,
      });
      final dest = Directory(p.join(tmp.path, 'out4'));
      final written = extractTarBz2(archive, dest);
      expect(written, isNotEmpty);
      expect(
        File(
          p.join(dest.path, 'sherpa-onnx-whisper-tiny/tiny-tokens.txt'),
        ).lengthSync(),
        2000000,
      );
    });
  });

  group('config resolution', () {
    test('single-file VAD resolves from modelsDirectory directly', () {
      final entry = vadCatalogEntry;
      File(p.join(tmp.path, 'silero_vad.onnx')).writeAsStringSync('VAD');
      final installer = VoiceModelInstaller(modelsDirectory: tmp);
      expect(installer.isInstalled(entry), isTrue);
      final cfg = installer.vadConfig(entry);
      expect(cfg.model, p.join(tmp.path, 'silero_vad.onnx'));
    });

    test('TTS config resolves model/tokens/dataDir once extracted', () {
      final entry = voiceModelCatalog.firstWhere(
        (e) => e.id == 'piper-en-amy-low',
      );
      final root = p.join(tmp.path, 'voice', entry.id);
      for (final rel in entry.files.values) {
        final target = p.join(root, rel);
        // espeak-ng-data is a directory in the real bundle.
        if (rel.endsWith('espeak-ng-data')) {
          Directory(target).createSync(recursive: true);
        } else {
          File(target)
            ..createSync(recursive: true)
            ..writeAsStringSync('x');
        }
      }
      final installer = VoiceModelInstaller(modelsDirectory: tmp);
      final cfg = installer.ttsConfig(entry);
      expect(cfg.type, TtsModelType.vits);
      expect(File(cfg.model).existsSync(), isTrue);
      expect(Directory(cfg.dataDir).existsSync(), isTrue);
    });

    test('missing files → not installed, config throws', () {
      final entry = voiceModelCatalog.firstWhere((e) => e.id == 'whisper-tiny');
      final installer = VoiceModelInstaller(modelsDirectory: tmp);
      expect(installer.isInstalled(entry), isFalse);
      expect(
        () => installer.asrConfig(entry),
        throwsA(isA<VoiceModelLoadFailure>()),
      );
    });
  });
}
