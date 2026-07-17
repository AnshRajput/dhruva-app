import 'dart:async';
import 'dart:io';

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/failures/app_failure.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/downloads/download_backend.dart';
import 'package:dhruva/data/downloads/download_manager.dart';
import 'package:dhruva/data/downloads/fake_download_backend.dart';
import 'package:dhruva/data/hf_api/models/hf_repo_file.dart';
import 'package:dhruva/data/hf_api/models/model_license_info.dart';
import 'package:dhruva/data/hf_api/models/quant_variant.dart';
import 'package:dhruva/features/models_hub/state/download_actions_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Waits for the first [DownloadProgress] matching [test] on [taskId].
Future<DownloadProgress> _nextWhere(
  Stream<DownloadProgress> stream,
  String taskId,
  bool Function(DownloadProgress) test,
) {
  final completer = Completer<DownloadProgress>();
  late StreamSubscription<DownloadProgress> sub;
  sub = stream.listen((event) {
    if (event.taskId == taskId && test(event)) {
      completer.complete(event);
      sub.cancel();
    }
  });
  return completer.future;
}

void main() {
  late AppDatabase db;
  late Directory modelsDir;
  late FakeDownloadBackend backend;
  late DownloadManager manager;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    modelsDir = Directory.systemTemp.createTempSync('dhruva_actions_test_');
    backend = FakeDownloadBackend();
    manager = DownloadManager(
      backend: backend,
      db: db,
      modelsDirectory: modelsDir,
    );
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        downloadManagerProvider.overrideWith((ref) async => manager),
        modelsDirectoryProvider.overrideWith((ref) async => modelsDir),
        deviceInfoServiceProvider.overrideWithValue(
          const FakeDeviceInfoService(
            memory: DeviceMemoryInfo(
              totalBytes: 8000000000,
              availableBytes: 4000000000,
            ),
            storage: DeviceStorageInfo(
              totalBytes: 64000000000,
              freeBytes: 32000000000,
            ),
          ),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await manager.dispose();
    await db.close();
    if (modelsDir.existsSync()) modelsDir.deleteSync(recursive: true);
  });

  DownloadRequest req({int expectedSizeBytes = 1000}) => DownloadRequest(
    repoId: 'bartowski/Llama-3.2-1B-Instruct-GGUF',
    fileName: 'Llama-3.2-1B-Instruct-Q4_K_M.gguf',
    url: Uri.parse('https://huggingface.co/x/resolve/main/x.gguf'),
    expectedSizeBytes: expectedSizeBytes,
  );

  test(
    'enqueue succeeds: not pending, no error, backend recorded it',
    () async {
      final request = req();
      await container
          .read(downloadActionsControllerProvider.notifier)
          .enqueue(request);

      final state = container.read(downloadActionsControllerProvider);
      expect(state.isPending(request.taskId), isFalse);
      expect(state.errorFor(request.taskId), isNull);
      expect(backend.enqueuedRequests, contains(request.taskId));
    },
  );

  test(
    'enqueue failure (insufficient space) is surfaced per task id',
    () async {
      final huge = req(expectedSizeBytes: 999999999999);
      await container
          .read(downloadActionsControllerProvider.notifier)
          .enqueue(huge);

      final state = container.read(downloadActionsControllerProvider);
      expect(state.isPending(huge.taskId), isFalse);
      expect(
        state.errorFor(huge.taskId),
        isA<StorageInsufficientSpaceFailure>(),
      );
      expect(backend.enqueuedRequests, isNot(contains(huge.taskId)));
    },
  );

  test('a failed enqueue does not affect another task id', () async {
    final huge = req(expectedSizeBytes: 999999999999);
    final small = DownloadRequest(
      repoId: 'bartowski/Qwen2.5-1.5B-Instruct-GGUF',
      fileName: 'Qwen2.5-1.5B-Instruct-Q4_K_M.gguf',
      url: Uri.parse('https://huggingface.co/x/resolve/main/y.gguf'),
      expectedSizeBytes: 1000,
    );
    await container
        .read(downloadActionsControllerProvider.notifier)
        .enqueue(huge);
    await container
        .read(downloadActionsControllerProvider.notifier)
        .enqueue(small);

    final state = container.read(downloadActionsControllerProvider);
    expect(state.errorFor(huge.taskId), isNotNull);
    expect(state.errorFor(small.taskId), isNull);
  });

  group('enqueueVisionQuant (Loop-7 T2 pairing)', () {
    const repoId = 'ggml-org/SmolVLM-500M-Instruct-GGUF';
    const modelFileName = 'SmolVLM-500M-Instruct-Q8_0.gguf';
    const mmprojFileName = 'mmproj-SmolVLM-500M-Instruct-Q8_0.gguf';
    const modelTaskId = '$repoId::$modelFileName';
    const mmprojTaskId = '$repoId::$mmprojFileName';
    const license = ModelLicenseInfo(
      license: 'apache-2.0',
      gatedStatus: HfGatedStatus.none,
    );

    QuantVariant visionQuant() => const QuantVariant(
      label: 'Q8_0',
      file: HfRepoFile(path: modelFileName, sizeBytes: 5),
      mmprojFile: HfRepoFile(path: mmprojFileName, sizeBytes: 5),
    );

    Future<DownloadActionsController> readyNotifier() async {
      final notifier = container.read(
        downloadActionsControllerProvider.notifier,
      );
      // Let the notifier's build()-kicked pairing-listener subscription
      // (fire-and-forget, since build() itself must stay synchronous) run
      // before relying on it to observe progress events below.
      await pumpEventQueue();
      return notifier;
    }

    test('downloads the model, then chain-enqueues the paired mmproj, and '
        'patches its path onto the SAME installed_models row once both '
        'complete — exactly one row, not two', () async {
      final notifier = await readyNotifier();
      await notifier.enqueueVisionQuant(
        repoId: repoId,
        quant: visionQuant(),
        license: license,
      );
      expect(backend.enqueuedRequests, contains(modelTaskId));
      expect(backend.enqueuedRequests, isNot(contains(mmprojTaskId)));

      final modelFile = File('${modelsDir.path}/$modelFileName')
        ..writeAsBytesSync([1, 2, 3, 4, 5]);
      backend.filePaths[modelTaskId] = modelFile.path;
      final modelDone = _nextWhere(
        manager.progress,
        modelTaskId,
        (p) => p.state == DownloadState.complete,
      );
      backend.emit(
        BackendStatusUpdate(modelTaskId, status: BackendTaskStatus.complete),
      );
      await modelDone;

      var row = await (db.select(
        db.installedModels,
      )..where((t) => t.repoId.equals(repoId))).getSingle();
      expect(row.isVision, isTrue);
      expect(row.mmprojPath, isNull); // not attached yet

      // The projector is chain-enqueued only AFTER the model completes —
      // give the fire-and-forget chain a beat to run.
      await pumpEventQueue();
      expect(backend.enqueuedRequests, contains(mmprojTaskId));

      final mmprojFile = File('${modelsDir.path}/$mmprojFileName')
        ..writeAsBytesSync([9, 9, 9, 9, 9]);
      backend.filePaths[mmprojTaskId] = mmprojFile.path;
      final mmprojDone = _nextWhere(
        manager.progress,
        mmprojTaskId,
        (p) => p.state == DownloadState.complete,
      );
      backend.emit(
        BackendStatusUpdate(mmprojTaskId, status: BackendTaskStatus.complete),
      );
      await mmprojDone;
      await pumpEventQueue(); // let attachProjector run

      row = await (db.select(
        db.installedModels,
      )..where((t) => t.repoId.equals(repoId))).getSingle();
      expect(row.mmprojPath, mmprojFile.path);
      expect(await db.select(db.installedModels).get(), hasLength(1));
    });

    test('the model download failing enqueues no projector at all', () async {
      final notifier = await readyNotifier();
      await notifier.enqueueVisionQuant(
        repoId: repoId,
        quant: visionQuant(),
        license: license,
      );

      final failed = _nextWhere(
        manager.progress,
        modelTaskId,
        (p) => p.state == DownloadState.failed,
      );
      backend.emit(
        BackendStatusUpdate(
          modelTaskId,
          status: BackendTaskStatus.failed,
          errorMessage: 'network dropped',
        ),
      );
      await failed;
      await pumpEventQueue();

      expect(backend.enqueuedRequests, isNot(contains(mmprojTaskId)));
      expect(await db.select(db.installedModels).get(), isEmpty);
    });

    test("the projector failing AFTER the model succeeds leaves the model's "
        "row in the 'needs projector' half-state (isVision true, mmprojPath "
        'null) — not lost, not duplicated — and surfaces the failure under '
        "the model's own taskId", () async {
      final notifier = await readyNotifier();
      await notifier.enqueueVisionQuant(
        repoId: repoId,
        quant: visionQuant(),
        license: license,
      );

      final modelFile = File('${modelsDir.path}/$modelFileName')
        ..writeAsBytesSync([1, 2, 3, 4, 5]);
      backend.filePaths[modelTaskId] = modelFile.path;
      final modelDone = _nextWhere(
        manager.progress,
        modelTaskId,
        (p) => p.state == DownloadState.complete,
      );
      backend.emit(
        BackendStatusUpdate(modelTaskId, status: BackendTaskStatus.complete),
      );
      await modelDone;
      await pumpEventQueue();

      final projectorFailed = _nextWhere(
        manager.progress,
        mmprojTaskId,
        (p) => p.state == DownloadState.failed,
      );
      backend.emit(
        BackendStatusUpdate(
          mmprojTaskId,
          status: BackendTaskStatus.failed,
          errorMessage: 'projector network dropped',
        ),
      );
      await projectorFailed;
      await pumpEventQueue();

      final row = await (db.select(
        db.installedModels,
      )..where((t) => t.repoId.equals(repoId))).getSingle();
      expect(row.isVision, isTrue);
      expect(row.mmprojPath, isNull); // needs-projector half-state
      expect(await db.select(db.installedModels).get(), hasLength(1));

      final state = container.read(downloadActionsControllerProvider);
      expect(state.errorFor(modelTaskId), isNotNull);
    });
  });
}
