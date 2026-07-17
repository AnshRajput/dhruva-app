import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/voice/voice_model_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('catalog invariants', () {
    test('ids are unique', () {
      final ids = voiceModelCatalog.map((e) => e.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('exactly one VAD entry, reachable via vadCatalogEntry', () {
      expect(
        voiceModelCatalog.where((e) => e.role == VoiceModelRole.vad),
        hasLength(1),
      );
      expect(vadCatalogEntry.role, VoiceModelRole.vad);
    });

    test('covers ASR + at least an English and a Hindi TTS voice', () {
      expect(
        voiceModelCatalog.any((e) => e.role == VoiceModelRole.asr),
        isTrue,
      );
      final tts = voiceModelCatalog.where((e) => e.role == VoiceModelRole.tts);
      expect(tts.any((e) => e.languages.contains('en')), isTrue);
      expect(tts.any((e) => e.languages.contains('hi')), isTrue);
    });

    test('archiveName is the URL basename', () {
      for (final e in voiceModelCatalog) {
        expect(e.archiveName, e.url.pathSegments.last);
        expect(e.archiveName, isNotEmpty);
      }
    });

    test('every entry declares size + license + the right file keys', () {
      const requiredKeys = {
        VoiceModelRole.asr: {'encoder', 'decoder', 'tokens'},
        VoiceModelRole.tts: {'model', 'tokens', 'dataDir'},
        VoiceModelRole.vad: {'model'},
      };
      for (final e in voiceModelCatalog) {
        expect(e.downloadSizeBytes, greaterThan(0), reason: e.id);
        expect(e.license, isNotEmpty, reason: e.id);
        expect(e.licenseUrl.scheme, 'https', reason: e.id);
        expect(e.files.keys.toSet(), requiredKeys[e.role], reason: e.id);
      }
    });

    test('only ASR/TTS bundles are archives; VAD is a single file', () {
      for (final e in voiceModelCatalog) {
        if (e.role == VoiceModelRole.vad) {
          expect(e.isArchive, isFalse);
        } else {
          expect(e.isArchive, isTrue);
          expect(e.archiveName, endsWith('.tar.bz2'));
        }
      }
    });
  });

  group('voiceModelDownloadRequest bridge', () {
    test('maps a catalog entry onto a DownloadRequest', () {
      final entry = vadCatalogEntry;
      final req = voiceModelDownloadRequest(entry);
      expect(req.repoId, 'sherpa-voice/${entry.id}');
      expect(req.fileName, entry.archiveName);
      expect(req.url, entry.url);
      expect(req.expectedSizeBytes, entry.downloadSizeBytes);
      expect(req.license, entry.license);
      // taskId is stable per repo+file so retries reuse the same backend task.
      expect(req.taskId, 'sherpa-voice/${entry.id}::${entry.archiveName}');
    });
  });
}
