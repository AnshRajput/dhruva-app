/// Curated voice-model catalog (Loop 6, D3).
///
/// Voice models are downloaded through the SAME resumable pipeline as GGUF
/// models (the `DownloadManager`); this file is only the curated data — verified
/// URLs, sizes, licenses, and the in-bundle file layout each model needs. Kept
/// pure (no `data/` import) so the download wiring lives in the DI layer, same
/// split as `EngineService` staying free of `background_downloader`.
///
/// All URLs/sizes verified with real HTTP HEAD requests on 2026-07-17 against
/// the k2-fsa/sherpa-onnx GitHub release assets. Sizes are the archive/file
/// content-length in bytes.
library;

/// What a voice model does. One catalog entry has exactly one role.
enum VoiceModelRole { asr, tts, vad }

/// One downloadable voice model.
final class VoiceCatalogEntry {
  final String id;
  final VoiceModelRole role;
  final String displayName;
  final String description;

  /// BCP-47-ish language tags the model handles. `['multilingual']` for whisper
  /// (covers Hindi/Hinglish via auto-detect).
  final List<String> languages;

  /// Direct download URL of the archive (ASR/TTS) or single file (VAD).
  final Uri url;

  /// content-length of [url] in bytes (verified).
  final int downloadSizeBytes;

  /// sha256 of the downloaded file, when known. sherpa's release assets don't
  /// publish per-file checksums, so this is null today — the `DownloadManager`
  /// still verifies size (see `verifyIntegrity`).
  final String? sha256;

  /// SPDX-ish license label + a URL to the authoritative terms.
  final String license;
  final Uri licenseUrl;

  /// True when [url] is a `.tar.bz2` bundle needing extraction (see
  /// `VoiceModelInstaller`); false for a single-file model.
  final bool isArchive;

  /// In-bundle (or, for single-file models, in-`modelsDirectory`) relative
  /// paths, keyed by the role's config fields:
  ///   asr → encoder, decoder, tokens
  ///   tts → model, tokens, dataDir
  ///   vad → model
  final Map<String, String> files;

  /// Rough device-tier guidance: minimum total RAM (MB) we'd run this on.
  /// Voice models are small; even the ASR is fine on the 4 GB floor.
  final int minRamMb;

  const VoiceCatalogEntry({
    required this.id,
    required this.role,
    required this.displayName,
    required this.description,
    required this.languages,
    required this.url,
    required this.downloadSizeBytes,
    required this.license,
    required this.licenseUrl,
    required this.isArchive,
    required this.files,
    this.sha256,
    this.minRamMb = 4096,
  });

  /// Local on-disk file name the `DownloadManager` writes (the URL basename).
  String get archiveName => url.pathSegments.last;
}

/// The curated set. Small and stable (changes on the order of "a new loop's
/// research", not per-release), so a hardcoded list beats a remote catalog
/// (YAGNI) — same call as `starterModelCatalog` for GGUF models. `final`, not
/// `const`, only because `Uri.parse` isn't a const expression.
final voiceModelCatalog = <VoiceCatalogEntry>[
  // --- VAD (required for turn-taking) --------------------------------------
  VoiceCatalogEntry(
    id: 'silero-vad',
    role: VoiceModelRole.vad,
    displayName: 'Silero VAD',
    description:
        'Voice-activity detector for turn-taking and barge-in. Tiny; '
        'always install this first.',
    languages: ['any'],
    url: _asr('silero_vad.onnx'),
    downloadSizeBytes: 643854, // ~629 KB, verified
    license: 'MIT',
    licenseUrl: _uri('https://github.com/snakers4/silero-vad'),
    isArchive: false,
    files: {'model': 'silero_vad.onnx'},
  ),

  // --- ASR (multilingual, incl. Hindi/Hinglish) ----------------------------
  VoiceCatalogEntry(
    id: 'whisper-tiny',
    role: VoiceModelRole.asr,
    displayName: 'Whisper Tiny (multilingual)',
    description:
        'OpenAI Whisper tiny, int8. Auto-detects language across ~99 '
        'languages including Hindi and code-switched Hinglish.',
    languages: ['multilingual'],
    url: _asr('sherpa-onnx-whisper-tiny.tar.bz2'),
    downloadSizeBytes: 116204861, // ~111 MB, verified
    license: 'MIT (OpenAI Whisper)',
    licenseUrl: _uri('https://github.com/openai/whisper/blob/main/LICENSE'),
    isArchive: true,
    files: {
      'encoder': 'sherpa-onnx-whisper-tiny/tiny-encoder.int8.onnx',
      'decoder': 'sherpa-onnx-whisper-tiny/tiny-decoder.int8.onnx',
      'tokens': 'sherpa-onnx-whisper-tiny/tiny-tokens.txt',
    },
  ),

  // --- TTS voices ----------------------------------------------------------
  VoiceCatalogEntry(
    id: 'piper-en-amy-low',
    role: VoiceModelRole.tts,
    displayName: 'Amy (English, US)',
    description: 'Piper VITS voice, 16 kHz. Default English voice.',
    languages: ['en'],
    url: _tts('vits-piper-en_US-amy-low.tar.bz2'),
    downloadSizeBytes: 67095344, // ~64 MB, verified
    license: 'Piper (MIT) / voice: Mycroft mimic3-voices — see MODEL_CARD',
    licenseUrl: _uri('https://github.com/MycroftAI/mimic3-voices'),
    isArchive: true,
    files: {
      'model': 'vits-piper-en_US-amy-low/en_US-amy-low.onnx',
      'tokens': 'vits-piper-en_US-amy-low/tokens.txt',
      'dataDir': 'vits-piper-en_US-amy-low/espeak-ng-data',
    },
  ),
  VoiceCatalogEntry(
    id: 'piper-hi-pratham-medium',
    role: VoiceModelRole.tts,
    displayName: 'Pratham (Hindi)',
    description: 'Piper VITS Hindi voice for Hindi/Hinglish replies.',
    languages: ['hi'],
    url: _tts('vits-piper-hi_IN-pratham-medium.tar.bz2'),
    downloadSizeBytes: 67238438, // ~64 MB, verified
    license: 'Piper (MIT) / voice: see MODEL_CARD',
    licenseUrl: _uri('https://github.com/rhasspy/piper'),
    isArchive: true,
    files: {
      'model': 'vits-piper-hi_IN-pratham-medium/hi_IN-pratham-medium.onnx',
      'tokens': 'vits-piper-hi_IN-pratham-medium/tokens.txt',
      'dataDir': 'vits-piper-hi_IN-pratham-medium/espeak-ng-data',
    },
  ),
];

/// The one VAD entry (there's exactly one; callers need it for every
/// turn-taking flow).
VoiceCatalogEntry get vadCatalogEntry =>
    voiceModelCatalog.firstWhere((e) => e.role == VoiceModelRole.vad);

Uri _uri(String s) => Uri.parse(s);

Uri _asr(String asset) => Uri.parse(
  'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/$asset',
);

Uri _tts(String asset) => Uri.parse(
  'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/$asset',
);
