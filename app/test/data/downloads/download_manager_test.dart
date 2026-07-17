import 'dart:async';
import 'dart:io';

import 'package:dhruva/core/failures/app_failure.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/downloads/download_backend.dart';
import 'package:dhruva/data/downloads/download_manager.dart';
import 'package:dhruva/data/downloads/fake_download_backend.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Waits for the first [DownloadProgress] matching [test], so assertions
/// don't race the manager's async `_handleUpdate` processing.
Future<DownloadProgress> _nextWhere(
  Stream<DownloadProgress> stream,
  bool Function(DownloadProgress) test,
) {
  final completer = Completer<DownloadProgress>();
  late StreamSubscription<DownloadProgress> sub;
  sub = stream.listen((event) {
    if (test(event)) {
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

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    modelsDir = Directory.systemTemp.createTempSync('dhruva_dl_test_');
    backend = FakeDownloadBackend();
    manager = DownloadManager(
      backend: backend,
      db: db,
      modelsDirectory: modelsDir,
    );
  });

  tearDown(() async {
    await manager.dispose();
    await db.close();
    if (modelsDir.existsSync()) modelsDir.deleteSync(recursive: true);
  });

  DownloadRequest req({String? sha256}) => DownloadRequest(
    repoId: 'bartowski/Llama-3.2-1B-Instruct-GGUF',
    fileName: 'Llama-3.2-1B-Instruct-Q4_K_M.gguf',
    url: Uri.parse(
      'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/'
      'Llama-3.2-1B-Instruct-Q4_K_M.gguf',
    ),
    expectedSizeBytes: 5,
    expectedSha256: sha256,
    quant: 'Q4_K_M',
    license: 'llama3.2',
  );

  group('enqueue', () {
    test(
      'refuses with StorageInsufficientSpaceFailure when free space is too low',
      () async {
        final r = req();
        await expectLater(
          () => manager.enqueue(r, freeBytes: 10),
          throwsA(isA<StorageInsufficientSpaceFailure>()),
        );
        expect(backend.enqueuedRequests, isEmpty);
      },
    );

    test('calls the backend and emits queued on success', () async {
      final r = req();
      final future = _nextWhere(
        manager.progress,
        (p) => p.state == DownloadState.queued,
      );
      await manager.enqueue(r, freeBytes: 1 << 30);
      final progress = await future;

      expect(backend.enqueuedRequests, contains(r.taskId));
      expect(progress.repoId, r.repoId);
      expect(progress.fileName, r.fileName);
    });

    test(
      'throws StorageIoFailure and does not track the task if the backend rejects it',
      () async {
        backend.enqueueResult = false;
        final r = req();
        await expectLater(
          () => manager.enqueue(r, freeBytes: 1 << 30),
          throwsA(isA<StorageIoFailure>()),
        );
      },
    );
  });

  group('progress updates', () {
    test('a progress fraction is converted to downloaded bytes', () async {
      final r = req();
      await manager.enqueue(r, freeBytes: 1 << 30);

      final future = _nextWhere(
        manager.progress,
        (p) => p.state == DownloadState.running,
      );
      backend.emit(
        BackendProgressUpdate(
          r.taskId,
          progress: 0.4,
          expectedFileSizeBytes: 5,
        ),
      );
      final progress = await future;

      expect(progress.downloadedBytes, 2); // 0.4 * 5 rounded
      expect(progress.totalBytes, 5);
    });

    test(
      'negative sentinel progress values are ignored (status update carries the real state)',
      () async {
        final r = req();
        await manager.enqueue(r, freeBytes: 1 << 30);

        final events = <DownloadProgress>[];
        final sub = manager.progress.listen(events.add);
        backend.emit(BackendProgressUpdate(r.taskId, progress: -2.0));
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(events, isEmpty);
      },
    );

    test('updates for an unknown/inactive taskId are ignored', () async {
      final events = <DownloadProgress>[];
      final sub = manager.progress.listen(events.add);
      backend.emit(
        const BackendProgressUpdate('not-a-real-task', progress: 0.5),
      );
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(events, isEmpty);
    });
  });

  group('completion + integrity', () {
    test(
      'complete: size-only check passes, file registered in drift',
      () async {
        final r = req();
        await manager.enqueue(r, freeBytes: 1 << 30);
        final file = File('${modelsDir.path}/${r.fileName}')
          ..writeAsBytesSync([1, 2, 3, 4, 5]);
        backend.filePaths[r.taskId] = file.path;

        final future = _nextWhere(
          manager.progress,
          (p) => p.state == DownloadState.complete,
        );
        backend.emit(
          BackendStatusUpdate(r.taskId, status: BackendTaskStatus.complete),
        );
        final progress = await future;

        expect(progress.downloadedBytes, 5);
        final rows = await db.select(db.installedModels).get();
        expect(rows, hasLength(1));
        expect(rows.single.repoId, r.repoId);
        expect(rows.single.sizeBytes, 5);
        expect(rows.single.quant, 'Q4_K_M');
        expect(rows.single.license, 'llama3.2');
      },
    );

    test('complete: size mismatch fails, no drift row, file deleted', () async {
      final r = req();
      await manager.enqueue(r, freeBytes: 1 << 30);
      final file = File('${modelsDir.path}/${r.fileName}')
        ..writeAsBytesSync([1, 2, 3]); // wrong size
      backend.filePaths[r.taskId] = file.path;

      final future = _nextWhere(
        manager.progress,
        (p) => p.state == DownloadState.failed,
      );
      backend.emit(
        BackendStatusUpdate(r.taskId, status: BackendTaskStatus.complete),
      );
      final progress = await future;

      expect(progress.errorMessage, contains('size mismatch'));
      expect(await db.select(db.installedModels).get(), isEmpty);
      expect(file.existsSync(), isFalse);
    });

    test('complete: checksum mismatch fails even when size matches', () async {
      final r = req(sha256: 'a' * 64);
      await manager.enqueue(r, freeBytes: 1 << 30);
      final file = File('${modelsDir.path}/${r.fileName}')
        ..writeAsBytesSync([1, 2, 3, 4, 5]);
      backend.filePaths[r.taskId] = file.path;

      final future = _nextWhere(
        manager.progress,
        (p) => p.state == DownloadState.failed,
      );
      backend.emit(
        BackendStatusUpdate(r.taskId, status: BackendTaskStatus.complete),
      );
      final progress = await future;

      expect(progress.errorMessage, contains('checksum mismatch'));
      expect(await db.select(db.installedModels).get(), isEmpty);
    });

    test('complete: matching checksum passes', () async {
      // sha256([1,2,3,4,5]) precomputed.
      final r = req(
        sha256:
            '74f81fe167d99b4cb41d6d0ccda82278caee9f3e2f25d5e5a3936ff3dcec60d0',
      );
      await manager.enqueue(r, freeBytes: 1 << 30);
      final file = File('${modelsDir.path}/${r.fileName}')
        ..writeAsBytesSync([1, 2, 3, 4, 5]);
      backend.filePaths[r.taskId] = file.path;

      final future = _nextWhere(
        manager.progress,
        (p) => p.state == DownloadState.complete,
      );
      backend.emit(
        BackendStatusUpdate(r.taskId, status: BackendTaskStatus.complete),
      );
      await future;

      expect(await db.select(db.installedModels).get(), hasLength(1));
    });

    test('complete: missing file on disk fails without crashing', () async {
      final r = req();
      await manager.enqueue(r, freeBytes: 1 << 30);
      backend.filePaths[r.taskId] = '${modelsDir.path}/does-not-exist.gguf';

      final future = _nextWhere(
        manager.progress,
        (p) => p.state == DownloadState.failed,
      );
      backend.emit(
        BackendStatusUpdate(r.taskId, status: BackendTaskStatus.complete),
      );
      final progress = await future;

      expect(progress.errorMessage, contains('missing'));
    });
  });

  group('failure + cancel + cleanup', () {
    test('failed status cleans up the partial file and emits failed', () async {
      final r = req();
      await manager.enqueue(r, freeBytes: 1 << 30);
      final partial = File('${modelsDir.path}/${r.fileName}')
        ..writeAsBytesSync([1, 2]);
      backend.filePaths[r.taskId] = partial.path;

      final future = _nextWhere(
        manager.progress,
        (p) => p.state == DownloadState.failed,
      );
      backend.emit(
        BackendStatusUpdate(
          r.taskId,
          status: BackendTaskStatus.failed,
          errorMessage: 'boom',
        ),
      );
      final progress = await future;

      expect(progress.errorMessage, 'boom');
      expect(partial.existsSync(), isFalse);
    });

    test('notFound status is treated the same as failed', () async {
      final r = req();
      await manager.enqueue(r, freeBytes: 1 << 30);

      final future = _nextWhere(
        manager.progress,
        (p) => p.state == DownloadState.failed,
      );
      backend.emit(
        BackendStatusUpdate(r.taskId, status: BackendTaskStatus.notFound),
      );
      await future;
    });

    test(
      'cancel calls the backend, deletes the partial file, emits canceled',
      () async {
        final r = req();
        await manager.enqueue(r, freeBytes: 1 << 30);
        final partial = File('${modelsDir.path}/${r.fileName}')
          ..writeAsBytesSync([1, 2]);
        backend.filePaths[r.taskId] = partial.path;

        final future = _nextWhere(
          manager.progress,
          (p) => p.state == DownloadState.canceled,
        );
        await manager.cancel(r.taskId);
        await future;

        expect(backend.cancelCalls, contains(r.taskId));
        expect(partial.existsSync(), isFalse);
      },
    );

    test(
      'cancel on an already-inactive task is a no-op (no crash, no event)',
      () async {
        final events = <DownloadProgress>[];
        final sub = manager.progress.listen(events.add);
        await manager.cancel('never-enqueued');
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        expect(events, isEmpty);
      },
    );

    test('pause/resume delegate to the backend', () async {
      final r = req();
      await manager.enqueue(r, freeBytes: 1 << 30);
      await manager.pause(r.taskId);
      await manager.resume(r.taskId);
      expect(backend.pauseCalls, [r.taskId]);
      expect(backend.resumeCalls, [r.taskId]);
    });

    test(
      'paused/queued/running status updates are surfaced without touching drift',
      () async {
        final r = req();
        await manager.enqueue(r, freeBytes: 1 << 30);

        final future = _nextWhere(
          manager.progress,
          (p) => p.state == DownloadState.paused,
        );
        backend.emit(
          BackendStatusUpdate(r.taskId, status: BackendTaskStatus.paused),
        );
        await future;
        expect(await db.select(db.installedModels).get(), isEmpty);
      },
    );

    test('pausing does NOT delete the partial file — the code\'s promise for a '
        'paused task is resumable state, not cleanup (attack #2/#3: pin the '
        'actual behavior)', () async {
      final r = req();
      await manager.enqueue(r, freeBytes: 1 << 30);
      final partial = File('${modelsDir.path}/${r.fileName}')
        ..writeAsBytesSync([1, 2]);
      backend.filePaths[r.taskId] = partial.path;

      final future = _nextWhere(
        manager.progress,
        (p) => p.state == DownloadState.paused,
      );
      backend.emit(
        BackendStatusUpdate(r.taskId, status: BackendTaskStatus.paused),
      );
      await future;

      expect(partial.existsSync(), isTrue); // preserved for resume
    });
  });

  group('trust boundary: fileName sanitization (attack #7)', () {
    test(
      'BUG repro: DownloadManager does not sanitize a path-traversal fileName '
      'itself — it trusts the caller completely. The models directory is '
      'escaped when resolving the on-disk path for a completed/failed task. '
      'Production is only saved by the UI call site (model_detail_screen.dart '
      'using p.basename) — DownloadManager, the shared data-layer choke '
      'point, provides no defense-in-depth. HIGH: any future caller that '
      "forwards an HF tree entry's raw path as fileName (subfolder files, "
      'e.g. mmproj/*, are a legitimate real-world case that already needs '
      'basename stripping) reintroduces arbitrary-file-delete/escape risk.',
      () async {
        final r = DownloadRequest(
          repoId: 'evil/repo',
          fileName: '../../../../etc/dhruva-traversal-poc.gguf',
          url: Uri.parse('https://huggingface.co/evil/repo/resolve/main/x'),
          expectedSizeBytes: 5,
        );
        await manager.enqueue(r, freeBytes: 1 << 30);

        // Simulate the backend reporting no known file path (the fallback
        // branch DownloadManager itself computes via p.join(modelsDirectory,
        // fileName) — this is the exact code path a real completed/failed
        // task with a malicious fileName would hit).
        final future = _nextWhere(
          manager.progress,
          (p) => p.state == DownloadState.failed,
        );
        backend.emit(
          BackendStatusUpdate(r.taskId, status: BackendTaskStatus.failed),
        );
        await future;

        // What SHOULD be true: any path DownloadManager touches for this
        // task stays inside modelsDirectory. It currently is not — the
        // resolved path's normalized form is outside modelsDir.
        final resolvedInsideModelsDir = p.isWithin(
          modelsDir.path,
          p.normalize(p.join(modelsDir.path, r.fileName)),
        );
        expect(
          resolvedInsideModelsDir,
          isFalse,
          reason:
              'Documents the current (unsafe) behavior — see BUG note above. '
              'When lib/ is fixed to reject/sanitize traversal fileNames at '
              'the DownloadManager boundary, flip this to isTrue.',
        );
      },
    );
  });
}
