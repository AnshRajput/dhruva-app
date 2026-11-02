// "100%" is never shown before the model is registered.

import 'package:dhruva/core/di/model_download.dart';
import 'package:dhruva/data/downloads/download_manager.dart';
import 'package:flutter_test/flutter_test.dart';

DownloadProgress _p(int done, int? total, [DownloadState? s]) =>
    DownloadProgress(
      taskId: 't',
      repoId: 'org/model',
      fileName: 'm.gguf',
      state: s ?? DownloadState.running,
      downloadedBytes: done,
      totalBytes: total,
    );

void main() {
  test('a fraction while bytes arrive', () {
    expect(downloadFraction(_p(250, 1000)), 0.25);
    expect(downloadFinishing(_p(250, 1000)), isFalse);
  });

  test('every byte here (or hashing) is Finishing up, with no fraction', () {
    for (final p in [
      _p(1000, 1000),
      _p(1200, 1000),
      _p(400, 1000, DownloadState.verifying),
    ]) {
      expect(downloadFinishing(p), isTrue);
      expect(downloadFraction(p), isNull);
    }
  });

  test('an unknown total is neither a fraction nor Finishing up', () {
    expect(downloadFraction(_p(500, null)), isNull);
    expect(downloadFinishing(_p(500, null)), isFalse);
    expect(downloadFinishing(_p(0, 0)), isFalse);
  });
}
