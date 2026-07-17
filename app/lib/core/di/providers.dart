/// Riverpod DI root (ADR-002: "all state in providers"). Every
/// cross-feature dependency — the engine, the database, network clients,
/// the download manager — is exposed here so `features/` code never
/// constructs a concrete implementation itself (`debug_chat` is the sole,
/// documented, temporary exception — see its own file).
///
/// Test/preview overrides: wrap in `ProviderScope(overrides: [...])`, e.g.
/// `engineServiceProvider.overrideWithValue(FakeEngineService(...))`.
library;

import 'dart:async' show unawaited;
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/db/database.dart';
import '../../data/downloads/background_downloader_backend.dart';
import '../../data/downloads/download_manager.dart';
import '../../data/downloads/storage_manager.dart';
import '../../data/hf_api/hf_api_client.dart';
import '../../engine_bindings/engine_service.dart';
import '../../engine_bindings/llama_engine_service.dart';
import '../device_info/device_info_service.dart';

/// The on-device inference engine. `LlamaEngineService` in production;
/// override with `FakeEngineService` in tests/widget previews.
final engineServiceProvider = Provider<EngineService>((ref) {
  final service = LlamaEngineService();
  ref.onDispose(() {
    // Fire-and-forget: Provider.onDispose can't be async. dispose() itself
    // is defensive (safe on an unloaded engine).
    unawaited(service.dispose());
  });
  return service;
});

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
