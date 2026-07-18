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
/// content-length in bytes. `sha256` for all 4 entries was self-computed on
/// 2026-07-18 (reviewer nit, Loop 6) by downloading each asset in full and
/// hashing it (`shasum -a 256`) — sherpa's release assets don't publish
/// per-file checksums themselves, so there's no upstream value to just
/// copy. Closes the bit-corruption gap `voice_model_installer_test.dart`'s
/// "trust boundary" group flagged (a same-length, bit-flipped transfer used
/// to sail through `DownloadManager`'s size-only check) — integrity is now
/// checked before extraction ever runs, same as GGUF models.
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

  /// sha256 of the downloaded file, self-computed (see the file doc comment
  /// — sherpa publishes no per-file checksums of its own). Verified by
  /// `DownloadManager` alongside size (see `verifyIntegrity`) before
  /// `VoiceModelInstaller` ever touches the file, so a bit-corrupted (but
  /// same-length) transfer is caught here rather than reaching the
  /// bzip2/tar decode.
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
    sha256: '9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6',
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
    sha256: 'c46116994e539aa165266d96b325252728429c12535eb9d8b6a2b10f129e66b1',
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
    sha256: 'c70f5284a09a7fd4ed203b39b2ff51cac1432b422b852eb647b481dade3cf639',
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
    sha256: '2084d321e1d2752f2b64ed3012ba27751df01a80da46f52920098cdcb7e35648',
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

/// The minimal set that makes hands-free work, as a single one-tap "voice
/// bundle" (WS5 acceptance: "install its models in one guided step"):
/// turn-taking (VAD) + speech-to-text (ASR) + one default English voice (TTS).
/// Extra voices (e.g. the Hindi Pratham TTS) stay optional add-ons in the
/// Voice tab — this is the "just make it work" starter set, not every model.
List<VoiceCatalogEntry> get voiceBundleEntries => [
  vadCatalogEntry,
  voiceModelCatalog.firstWhere((e) => e.role == VoiceModelRole.asr),
  voiceModelCatalog.firstWhere((e) => e.id == 'piper-en-amy-low'),
];

Uri _uri(String s) => Uri.parse(s);

Uri _asr(String asset) => Uri.parse(
  'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/$asset',
);

Uri _tts(String asset) => Uri.parse(
  'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/$asset',
);
