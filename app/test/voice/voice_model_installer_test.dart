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
