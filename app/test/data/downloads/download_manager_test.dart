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
      expect(progress.failure, isA<StorageCorruptFileFailure>());
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
      expect(progress.failure, isA<StorageNotFoundFailure>());
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
      expect(progress.failure, isA<NetworkUnknownFailure>());
      expect(partial.existsSync(), isFalse);
    });

    test(
      'notFound status is treated the same as failed, typed as an HTTP 404',
      () async {
        final r = req();
        await manager.enqueue(r, freeBytes: 1 << 30);

        final future = _nextWhere(
          manager.progress,
          (p) => p.state == DownloadState.failed,
        );
        backend.emit(
          BackendStatusUpdate(r.taskId, status: BackendTaskStatus.notFound),
        );
        final progress = await future;

        expect(
          progress.failure,
          isA<NetworkHttpFailure>().having(
            (e) => e.statusCode,
            'statusCode',
            404,
          ),
        );
      },
    );

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

  group('trust boundary: fileName sanitization (attack #7 — FIXED)', () {
    test('a path-traversal fileName is sanitized at the DownloadManager choke '
        'point (enqueue), not left to the UI call site: it is flattened to '
        'its basename, and every subsequent path DownloadManager touches for '
        'that task stays inside modelsDirectory.', () async {
      final r = DownloadRequest(
        repoId: 'evil/repo',
        fileName: '../../../../etc/dhruva-traversal-poc.gguf',
        url: Uri.parse('https://huggingface.co/evil/repo/resolve/main/x'),
        expectedSizeBytes: 5,
      );

      final queuedFuture = _nextWhere(
        manager.progress,
        (p) => p.state == DownloadState.queued,
      );
      await manager.enqueue(r, freeBytes: 1 << 30);
      final queued = await queuedFuture;

      // Sanitized to a plain basename — the taskId the manager actually
      // tracks (and reports back on the progress stream) reflects that,
      // not the caller's original, unsanitized `r.taskId`.
      expect(queued.fileName, 'dhruva-traversal-poc.gguf');
      expect(queued.taskId, 'evil/repo::dhruva-traversal-poc.gguf');
      expect(backend.enqueuedRequests.keys, contains(queued.taskId));
      expect(
        backend.enqueuedRequests[queued.taskId]!.fileName,
        'dhruva-traversal-poc.gguf',
      );

      final resolvedPath = p.normalize(p.join(modelsDir.path, queued.fileName));
      expect(
        p.isWithin(modelsDir.path, resolvedPath),
        isTrue,
        reason: 'the on-disk path must stay inside modelsDirectory',
      );
    });

    test(
      'a legitimate subfolder path (e.g. an HF mmproj file) is flattened '
      'the same way the traversal case is — the local fileName is the '
      'basename, but the remote resolve URL keeps the original subfolder '
      'path (they are separate fields, only fileName is sanitized).',
      () async {
        final r = DownloadRequest(
          repoId: 'ggml-org/SmolVLM2-2.2B-Instruct-GGUF',
          fileName: 'mmproj/mmproj-Q8_0.gguf',
          url: Uri.parse(
            'https://huggingface.co/ggml-org/SmolVLM2-2.2B-Instruct-GGUF/'
            'resolve/main/mmproj/mmproj-Q8_0.gguf',
          ),
          expectedSizeBytes: 5,
        );

        final queuedFuture = _nextWhere(
          manager.progress,
          (p) => p.state == DownloadState.queued,
        );
        await manager.enqueue(r, freeBytes: 1 << 30);
        final queued = await queuedFuture;

        expect(queued.fileName, 'mmproj-Q8_0.gguf');
        final enqueued = backend.enqueuedRequests[queued.taskId]!;
        expect(enqueued.fileName, 'mmproj-Q8_0.gguf');
        expect(enqueued.url.toString(), contains('/mmproj/mmproj-Q8_0.gguf'));
      },
    );

    test('a fileName that sanitizes to nothing usable is rejected with '
        'ValidationFailure before anything reaches the backend', () async {
      for (final bad in ['..', '.', '', '../..', '///']) {
        final r = DownloadRequest(
          repoId: 'evil/repo',
          fileName: bad,
          url: Uri.parse('https://huggingface.co/evil/repo/resolve/main/x'),
          expectedSizeBytes: 5,
        );
        await expectLater(
          () => manager.enqueue(r, freeBytes: 1 << 30),
          throwsA(isA<ValidationFailure>()),
          reason: 'fileName: "$bad"',
        );
      }
      expect(backend.enqueuedRequests, isEmpty);
    });
  });
}
