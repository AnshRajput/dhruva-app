/// Riverpod DI root (ADR-002: "all state in providers"). Every
/// cross-feature dependency — the engine, the database, network clients,
/// the download manager — is exposed here so `features/` code never
/// constructs a concrete implementation itself. (`debug_chat` was the sole,
/// documented, temporary exception through Loop 3 — deleted in Loop 4 now
/// that `features/chat` is the real thing.)
///
/// Test/preview overrides: wrap in `ProviderScope(overrides: [...])`, e.g.
/// `engineServiceProvider.overrideWithValue(FakeEngineService(...))`.
library;

import 'dart:async' show unawaited;
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/characters/character_repository.dart';
import '../../data/chat/chat_repository.dart';
import '../../data/db/database.dart';
import '../../data/downloads/background_downloader_backend.dart';
import '../../data/downloads/download_manager.dart';
import '../../data/downloads/storage_manager.dart';
import '../../data/hf_api/hf_api_client.dart';
import '../../engine_bindings/engine_service.dart';
import '../../engine_bindings/llama_engine_service.dart';
import '../../voice/mic_audio_source.dart';
import '../../voice/sherpa_voice_service.dart';
import '../../voice/voice_model_catalog.dart';
import '../../voice/voice_model_installer.dart';
import '../../voice/voice_player.dart';
import '../../voice/voice_service.dart';
import '../device_info/device_info_service.dart';

/// The on-device inference engine. `LlamaEngineService` in production;
/// override with `FakeEngineService` in tests/widget previews.
final engineServiceProvider = Provider<EngineService>((ref) {
  // Android ships the native libs inside the AAR (jni/arm64-v8a/libllama.so),
  // dlopen'd by basename — Android resolves it from the app's lib dir, and its
  // NEEDED deps (libggml*, libmtmd) alongside. iOS/macOS static-link the
  // xcframework/dylib into the process, so the worker loads from the process.
  final service = LlamaEngineService(
    libraryPath: Platform.isAndroid ? 'libllama.so' : null,
  );
  ref.onDispose(() {
    // Fire-and-forget: Provider.onDispose can't be async. dispose() itself
    // is defensive (safe on an unloaded engine).
    unawaited(service.dispose());
  });
  return service;
});

/// On-device voice (Loop 6): STT + TTS + Silero VAD via sherpa_onnx.
/// `SherpaVoiceService` in production (native libs resolved from the app
/// bundle → `libraryDirectory` null); override with `FakeVoiceService` in
/// tests/previews. The worker isolate spins up lazily on first use.
final voiceServiceProvider = Provider<VoiceService>((ref) {
  final service = SherpaVoiceService();
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

/// The device mic (Loop 6 T2): `MicAudioSource` in production; override with
/// `FakeMicSource` in tests/previews (same seam as [voiceServiceProvider]).
final micSourceProvider = Provider<MicSource>((ref) {
  final source = MicAudioSource();
  ref.onDispose(() => unawaited(source.dispose()));
  return source;
});

/// TTS playback (Loop 6 T2): `VoicePlayer` in production; override with
/// `FakeAudioSink` in tests/previews.
final audioSinkProvider = Provider<AudioSink>((ref) {
  final sink = VoicePlayer();
  ref.onDispose(() => unawaited(sink.dispose()));
  return sink;
});

/// Resolves + extracts downloaded voice-model bundles under `models/voice/`.
/// Pairs with the `DownloadManager` (which does the resumable fetch) — see
/// [voiceModelDownloadRequest].
final voiceModelInstallerProvider = FutureProvider<VoiceModelInstaller>((
  ref,
) async {
  final modelsDir = await ref.watch(modelsDirectoryProvider.future);
  return VoiceModelInstaller(modelsDirectory: modelsDir);
});

/// Bridges a curated [VoiceCatalogEntry] onto the EXISTING download pipeline —
/// voice models ride the same resumable, integrity-checked, storage-guarded
/// path as GGUF models (D3). Kept here (not in `voice/`) so the catalog stays
/// free of the `data/downloads` dependency.
DownloadRequest voiceModelDownloadRequest(VoiceCatalogEntry entry) {
  return DownloadRequest(
    repoId: 'sherpa-voice/${entry.id}',
    fileName: entry.archiveName,
    url: entry.url,
    expectedSizeBytes: entry.downloadSizeBytes,
    expectedSha256: entry.sha256,
    quant: null,
    license: entry.license,
  );
}

final deviceInfoServiceProvider = Provider<DeviceInfoService>((ref) {
  return PluginDeviceInfoService();
});

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final hfApiClientProvider = Provider<HfApiClient>((ref) {
  final client = HfApiClient();
  ref.onDispose(client.close);
  return client;
});

/// Directory GGUF files are downloaded/imported into:
/// `<application support dir>/models/`.
final modelsDirectoryProvider = FutureProvider<Directory>((ref) async {
  final supportDir = await getApplicationSupportDirectory();
  final modelsDir = Directory('${supportDir.path}/models');
  await modelsDir.create(recursive: true);
  return modelsDir;
});

final downloadManagerProvider = FutureProvider<DownloadManager>((ref) async {
  final modelsDir = await ref.watch(modelsDirectoryProvider.future);
  final manager = DownloadManager(
    backend: BackgroundDownloaderBackend(),
    db: ref.watch(appDatabaseProvider),
    modelsDirectory: modelsDir,
  );
  // Rebuilds in-flight/late-completed tasks from the backend's own
  // persistent tracking before this manager is handed out — see
  // DownloadManager.init's doc comment (app-restart rehydration).
  await manager.init();
  ref.onDispose(() => unawaited(manager.dispose()));
  return manager;
});

final storageManagerProvider = Provider<StorageManager>((ref) {
  return StorageManager(
    db: ref.watch(appDatabaseProvider),
    deviceInfo: ref.watch(deviceInfoServiceProvider),
  );
});

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(db: ref.watch(appDatabaseProvider));
});

final characterRepositoryProvider = Provider<CharacterRepository>((ref) {
  final repo = CharacterRepository(db: ref.watch(appDatabaseProvider));
  // Fire-and-forget: idempotent, tolerates the starter-pack asset being
  // absent (see CharacterRepository.seedBuiltInsIfPresent), so there's
  // nothing worth blocking provider construction on.
  unawaited(repo.seedBuiltInsIfPresent());
  return repo;
});
