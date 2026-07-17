// Attack #1-#4 (Loop 3 QA gate): a genuine integration-style E2E test.
//
// `BackgroundDownloaderBackend` (the production `DownloadBackend`) needs
// platform channels and cannot run under `flutter test` — documented in its
// own file. So this test builds a small `DownloadBackend` that does REAL
// network I/O against a REAL `dart:io HttpServer` bound to loopback, and
// drives the REAL `DownloadManager` + `HfApiClient` through the full
// search -> detail -> enqueue -> progress -> completion -> integrity ->
// drift-row flow. Only the HF JSON endpoints are mocked (per the QA brief:
// never hit huggingface.co in tests) — the actual file bytes flow over a
// real socket, through the real `DownloadManager` orchestration, exactly as
// attack #1 requires.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dhruva/core/failures/app_failure.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/downloads/download_backend.dart';
import 'package:dhruva/data/downloads/download_manager.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/mock_hf_client.dart';

/// A real GGUF-magic file's bytes: "GGUF" + a deterministic ~2MB filler
/// payload — big enough to observe multiple real progress events over
/// loopback, small enough to keep the suite fast.
Uint8List _realGgufBytes({int size = 2 * 1024 * 1024}) {
  final bytes = Uint8List(size);
  bytes[0] = 0x47; // G
  bytes[1] = 0x47; // G
  bytes[2] = 0x55; // U
  bytes[3] = 0x46; // F
  for (var i = 4; i < size; i++) {
    bytes[i] = i % 251;
  }
  return bytes;
}

/// Real loopback HTTP server serving one file's bytes, with HTTP Range
/// support (so resume is a genuine range request, not a re-download) and an
/// optional mid-stream kill (so "offline" is a genuine dropped connection,
/// not a synthetic exception).
class _LocalFileServer {
  final Uint8List content;
  late final HttpServer _server;

  /// If >= 0, the response is cut off after this many bytes of the
  /// (possibly range-offset) body and the connection is closed without
  /// completing the declared Content-Length — a real "connection died
  /// mid-transfer", not a mocked failure.
  int killAfterBytes = -1;
  bool sawRangeRequest = false;

  _LocalFileServer(this.content);

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_serve());
  }

  int get port => _server.port;
  Uri get baseUri => Uri.parse('http://127.0.0.1:$port');

  Future<void> _serve() async {
    await for (final request in _server) {
      unawaited(_handle(request));
    }
  }

  Future<void> _handle(HttpRequest request) async {
    var start = 0;
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    if (rangeHeader != null) {
      sawRangeRequest = true;
      final match = RegExp(r'bytes=(\d+)-').firstMatch(rangeHeader);
      if (match != null) start = int.parse(match.group(1)!);
    }
    final body = content.sublist(start);
    final response = request.response;
    response.statusCode = rangeHeader != null
        ? HttpStatus.partialContent
        : HttpStatus.ok;
    response.headers.contentLength = body.length;

    const chunkSize = 32 * 1024;
    var sent = 0;
    var killed = false;
    for (var offset = 0; offset < body.length; offset += chunkSize) {
      if (killAfterBytes >= 0 && sent >= killAfterBytes) {
        killed = true;
        break;
      }
      final end = (offset + chunkSize < body.length)
          ? offset + chunkSize
          : body.length;
      response.add(body.sublist(offset, end));
      await response.flush();
      sent += end - offset;
      // Slow enough that a test can observe partial progress and act on it
      // (pause) before loopback finishes the whole 2MB transfer.
      await Future<void>.delayed(const Duration(milliseconds: 15));
    }
    unawaited(response.close().catchError((_) {}));
    if (killed) return; // connection closes short of the declared length
  }

  Future<void> stop() => _server.close(force: true);
}

/// Real-network `DownloadBackend`: streams bytes off a real socket into a
/// real file, with genuine HTTP Range-based pause/resume. This is the stand-
/// in the QA brief allows when the production backend can't run under
/// `flutter test` — it still exercises DownloadManager's real orchestration
/// end to end over a real localhost connection.
class _LocalHttpDownloadBackend implements DownloadBackend {
  final HttpClient _client = HttpClient();
  final _controller = StreamController<BackendUpdate>.broadcast();
  final Map<String, BackendDownloadRequest> _requests = {};
  final Map<String, String> _paths = {};
  final Map<String, StreamSubscription<List<int>>> _subs = {};
  final Map<String, IOSink> _sinks = {};

  @override
  Stream<BackendUpdate> get updates => _controller.stream;

  @override
  Future<bool> enqueue(BackendDownloadRequest request) async {
    _requests[request.taskId] = request;
    final path = '${request.directoryPath}/${request.fileName}';
    _paths[request.taskId] = path;
    unawaited(_run(request, path, fromOffset: 0));
    return true;
  }

  Future<void> _run(
    BackendDownloadRequest request,
    String path, {
    required int fromOffset,
  }) async {
    _controller.add(
      BackendStatusUpdate(request.taskId, status: BackendTaskStatus.running),
    );
    try {
      final httpReq = await _client.getUrl(request.url);
      if (fromOffset > 0) {
        httpReq.headers.set(HttpHeaders.rangeHeader, 'bytes=$fromOffset-');
      }
      final response = await httpReq.close();
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        _controller.add(
          BackendStatusUpdate(
            request.taskId,
            status: BackendTaskStatus.failed,
            errorMessage: 'HTTP ${response.statusCode}',
          ),
        );
        return;
      }
      final total = response.contentLength >= 0
          ? fromOffset + response.contentLength
          : null;
      final sink = File(
        path,
      ).openWrite(mode: fromOffset > 0 ? FileMode.append : FileMode.write);
      _sinks[request.taskId] = sink;
      var received = fromOffset;
      var hadError = false;
      final done = Completer<void>();
      // Cancelled via the `_subs` map in pause()/cancel()/dispose() below.
      // ignore: cancel_subscriptions
      final sub = response.listen(
        (chunk) {
          sink.add(chunk);
          received += chunk.length;
          _controller.add(
            BackendProgressUpdate(
              request.taskId,
              progress: (total != null && total > 0) ? received / total : 0,
              expectedFileSizeBytes: total,
            ),
          );
        },
        onDone: () async {
          await sink.flush();
          await sink.close();
          _sinks.remove(request.taskId);
          if (!done.isCompleted) done.complete();
        },
        onError: (Object e) async {
          hadError = true;
          await sink.flush();
          await sink.close();
          _sinks.remove(request.taskId);
          if (!done.isCompleted) done.complete();
          _controller.add(
            BackendStatusUpdate(
              request.taskId,
              status: BackendTaskStatus.failed,
              errorMessage: e.toString(),
            ),
          );
        },
        cancelOnError: true,
      );
      _subs[request.taskId] = sub;
      await done.future;
      // A clean pause()/cancel() cancels the subscription directly (and
      // removes it from `_subs`/`_sinks` itself), so this line is only
      // reached via a genuine end-of-stream or a genuine transfer error —
      // never emit a spurious "complete" behind a "failed" that already
      // fired above.
      if (!hadError && _subs[request.taskId] == sub) {
        _controller.add(
          BackendStatusUpdate(
            request.taskId,
            status: BackendTaskStatus.complete,
          ),
        );
      }
    } catch (e) {
      _controller.add(
        BackendStatusUpdate(
          request.taskId,
          status: BackendTaskStatus.failed,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  /// Stops receiving and flushes/closes whatever was written so far, so the
  /// on-disk file genuinely reflects the bytes received before this call —
  /// not whatever happened to still be sitting in the `IOSink`'s buffer.
  Future<void> _stopAndFlush(String taskId) async {
    await _subs.remove(taskId)?.cancel();
    final sink = _sinks.remove(taskId);
    if (sink != null) {
      await sink.flush();
      await sink.close();
    }
  }

  @override
  Future<bool> pause(String taskId) async {
    await _stopAndFlush(taskId);
    _controller.add(
      BackendStatusUpdate(taskId, status: BackendTaskStatus.paused),
    );
    return true;
  }

  @override
  Future<bool> resume(String taskId) async {
    final request = _requests[taskId];
    final path = _paths[taskId];
    if (request == null || path == null) return false;
    final offset = File(path).existsSync() ? File(path).lengthSync() : 0;
    unawaited(_run(request, path, fromOffset: offset));
    return true;
  }

  @override
  Future<bool> cancel(String taskId) async {
    await _stopAndFlush(taskId);
    _controller.add(
      BackendStatusUpdate(taskId, status: BackendTaskStatus.canceled),
    );
    return true;
  }

  @override
  Future<String?> filePathFor(String taskId) async => _paths[taskId];

  // This backend has no persistent state (it's a fresh in-memory stand-in
  // per test, not the real plugin's on-disk task database) — restart
  // rehydration isn't what this file tests (see download_manager_test.dart
  // for that), so there's nothing to return.
  @override
  Future<List<RehydratedTask>> rehydrate() async => const [];

  @override
  Future<void> flushMissedUpdates() async {}

  Future<void> dispose() async {
    for (final sub in _subs.values) {
      await sub.cancel();
    }
    for (final sink in _sinks.values) {
      await sink.close();
    }
    await _controller.close();
    _client.close(force: true);
  }
}

Future<T> _await<T>(Future<T> future, {String? reason}) =>
    future.timeout(const Duration(seconds: 10));

void main() {
  late Directory modelsDir;
  late AppDatabase db;
  late _LocalFileServer server;
  late _LocalHttpDownloadBackend backend;
  late DownloadManager manager;
  late Uint8List content;
  late String contentSha256;

  setUp(() async {
    modelsDir = Directory.systemTemp.createTempSync('dhruva_e2e_test_');
    db = AppDatabase(NativeDatabase.memory());
    content = _realGgufBytes();
    contentSha256 = sha256.convert(content).toString();
    server = _LocalFileServer(content);
    await server.start();
    backend = _LocalHttpDownloadBackend();
    manager = DownloadManager(
      backend: backend,
      db: db,
      modelsDirectory: modelsDir,
    );
  });

  tearDown(() async {
    await manager.dispose();
    await backend.dispose();
    await server.stop();
    await db.close();
    if (modelsDir.existsSync()) modelsDir.deleteSync(recursive: true);
  });

  /// Drives the real search -> detail -> quant-selection flow through the
  /// real `HfApiClient` (JSON mocked, per the QA brief), pointed at the
  /// local server as its base URL so `resolveDownloadUrl` — real,
  /// unmocked, production code — naturally builds a URL back to our real
  /// socket.
  Future<DownloadRequest> searchAndBuildRequest({
    String? expectedSha256,
  }) async {
    const repoId = 'local/e2e-test-repo';
    const fileName = 'e2e-test-model-Q4_K_M.gguf';
    final client = mockHfClient(
      MockClient((request) async {
        if (request.url.path.contains('/api/models') &&
            !request.url.path.contains(repoId)) {
          return http.Response(
            jsonEncode([
              {
                'id': repoId,
                'likes': 1,
                'downloads': 1,
                'tags': ['gguf', 'license:apache-2.0'],
                'pipeline_tag': 'text-generation',
              },
            ]),
            200,
          );
        }
        if (request.url.path.endsWith('/tree/main')) {
          return http.Response(
            jsonEncode([
              {
                'type': 'file',
                'path': fileName,
                'size': content.length,
                if (expectedSha256 != null) 'lfs': {'oid': expectedSha256},
              },
            ]),
            200,
          );
        }
        // getModelLicenseInfo
        return http.Response(
          jsonEncode({
            'id': repoId,
            'license': 'apache-2.0',
            'gated': false,
            'tags': ['gguf', 'license:apache-2.0'],
          }),
          200,
        );
      }),
      baseUrl: server.baseUri,
    );
    addTearDown(client.close);

    final search = await client.searchGgufModels(query: 'e2e');
    expect(search.items, hasLength(1));
    expect(search.items.single.id, repoId);

    final files = await client.getRepoFiles(repoId);
    final variants = client.quantVariantsFrom(files);
    expect(variants, hasLength(1));
    final variant = variants.single;

    final license = await client.getModelLicenseInfo(repoId);
    expect(license.requiresAuth, isFalse);

    return DownloadRequest(
      repoId: repoId,
      fileName: variant.file.path,
      url: client.resolveDownloadUrl(repoId, variant.file.path),
      expectedSizeBytes: variant.file.sizeBytes,
      expectedSha256: variant.file.sha256,
      quant: variant.label,
      license: license.license,
      gated: license.requiresAuth,
    );
  }

  test(
    'full E2E: search -> detail -> enqueue -> real progress -> completion -> '
    'integrity pass -> installed drift row (attack #1)',
    () async {
      final request = await searchAndBuildRequest(
        expectedSha256: contentSha256,
      );

      final progressEvents = <DownloadProgress>[];
      final sub = manager.progress.listen(progressEvents.add);
      addTearDown(sub.cancel);

      await manager.enqueue(request, freeBytes: 1 << 30);
      final finalState = await _await(
        manager.progress.firstWhere(
          (p) =>
              p.state == DownloadState.complete ||
              p.state == DownloadState.failed,
        ),
      );

      expect(finalState.state, DownloadState.complete);
      expect(finalState.downloadedBytes, content.length);

      // Real bytes really flowed over the real socket: at least one
      // intermediate `running` event with partial progress was observed.
      expect(
        progressEvents.any(
          (p) =>
              p.state == DownloadState.running &&
              p.downloadedBytes > 0 &&
              p.downloadedBytes < content.length,
        ),
        isTrue,
        reason: 'expected at least one genuine partial-progress event',
      );

      final rows = await db.select(db.installedModels).get();
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.repoId, request.repoId);
      expect(row.sizeBytes, content.length);
      expect(row.sha256, contentSha256);
      final onDisk = File(row.localPath).readAsBytesSync();
      expect(onDisk, content); // byte-for-byte, not just size-equal
    },
  );

  test(
    'offline mid-download: connection dies partway -> failed status, partial '
    'file cleaned up, typed as a NetworkUnknownFailure (attack #2 — FIXED: '
    'this used to pin errorMessage as a plain String with no typed AppFailure '
    'reconstructed for async backend failures; DownloadManager now always '
    'attaches one, even though a bare "failed" status carries no further '
    'detail from the plugin than the message itself)',
    () async {
      server.killAfterBytes = 400 * 1024; // die well before EOF
      final request = await searchAndBuildRequest(
        expectedSha256: contentSha256,
      );

      await manager.enqueue(request, freeBytes: 1 << 30);
      final finalState = await _await(
        manager.progress.firstWhere((p) => p.state == DownloadState.failed),
      );

      expect(finalState.state, DownloadState.failed);
      expect(finalState.errorMessage, isNotNull);
      expect(finalState.errorMessage, isA<String>());
      expect(finalState.failure, isA<NetworkUnknownFailure>());

      // The code's actual promise on a failed task: no partial file left
      // behind, and nothing registered in drift.
      final path = '${modelsDir.path}/${request.fileName}';
      expect(File(path).existsSync(), isFalse);
      expect(await db.select(db.installedModels).get(), isEmpty);
    },
  );

  test(
    'resume: pause mid-transfer -> resume issues a real HTTP Range request '
    'from the on-disk offset -> completes with correct final bytes (attack #3)',
    () async {
      final request = await searchAndBuildRequest(
        expectedSha256: contentSha256,
      );

      await manager.enqueue(request, freeBytes: 1 << 30);
      // Wait for real partial progress, then pause mid-stream.
      await _await(
        manager.progress.firstWhere(
          (p) => p.state == DownloadState.running && p.downloadedBytes > 0,
        ),
      );
      await manager.pause(request.taskId);
      await _await(
        manager.progress.firstWhere((p) => p.state == DownloadState.paused),
      );

      final path = '${modelsDir.path}/${request.fileName}';
      final partialSize = File(path).lengthSync();
      expect(partialSize, greaterThan(0));
      expect(partialSize, lessThan(content.length)); // genuinely partial

      await manager.resume(request.taskId);
      final finalState = await _await(
        manager.progress.firstWhere(
          (p) =>
              p.state == DownloadState.complete ||
              p.state == DownloadState.failed,
        ),
      );

      expect(finalState.state, DownloadState.complete);
      expect(server.sawRangeRequest, isTrue); // genuine range-based resume
      final onDisk = File(path).readAsBytesSync();
      expect(onDisk, content); // resumed bytes are correct, not corrupted

      final rows = await db.select(db.installedModels).get();
      expect(rows, hasLength(1));
      expect(rows.single.sha256, contentSha256);
    },
  );

  test('corrupt file: server serves content whose real sha256 does not match '
      'the declared metadata -> integrity check fails -> file deleted, not '
      'registered (attack #4, over a real download)', () async {
    final request = await searchAndBuildRequest(
      expectedSha256: 'a' * 64, // wrong on purpose
    );

    await manager.enqueue(request, freeBytes: 1 << 30);
    final finalState = await _await(
      manager.progress.firstWhere((p) => p.state == DownloadState.failed),
    );

    expect(finalState.errorMessage, contains('checksum mismatch'));
    final path = '${modelsDir.path}/${request.fileName}';
    expect(File(path).existsSync(), isFalse);
    expect(await db.select(db.installedModels).get(), isEmpty);
  });

  test(
    'corrupt file: declared size does not match the real bytes served -> '
    'integrity check fails before checksum is even computed (attack #4)',
    () async {
      final request = await searchAndBuildRequest(expectedSha256: null);
      final wrongSizeRequest = DownloadRequest(
        repoId: request.repoId,
        fileName: request.fileName,
        url: request.url,
        expectedSizeBytes: request.expectedSizeBytes - 1, // wrong on purpose
        quant: request.quant,
        license: request.license,
      );

      await manager.enqueue(wrongSizeRequest, freeBytes: 1 << 30);
      final finalState = await _await(
        manager.progress.firstWhere((p) => p.state == DownloadState.failed),
      );

      expect(finalState.errorMessage, contains('size mismatch'));
      final path = '${modelsDir.path}/${request.fileName}';
      expect(File(path).existsSync(), isFalse);
      expect(await db.select(db.installedModels).get(), isEmpty);
    },
  );
}
