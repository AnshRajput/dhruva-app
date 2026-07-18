import 'package:dhruva/data/downloads/download_manager.dart';
import 'package:flutter_test/flutter_test.dart';

DownloadProgress _p({
  double speed = -1,
  Duration eta = const Duration(seconds: -1),
}) => DownloadProgress(
  taskId: 't',
  repoId: 'r',
  fileName: 'f',
  state: DownloadState.running,
  downloadedBytes: 1,
  totalBytes: 10,
  networkSpeedMBs: speed,
  timeRemaining: eta,
);

void main() {
  group('DownloadProgress.etaLabel (honest — nothing when unknown)', () {
    test('null when neither speed nor ETA is known', () {
      expect(_p().etaLabel, isNull);
    });

    test('formats MB/s and m:ss when both known', () {
      expect(
        _p(speed: 3.14, eta: const Duration(seconds: 45)).etaLabel,
        '3.1 MB/s · 0:45 left',
      );
    });

    test('sub-1 MB/s renders as kB/s', () {
      expect(_p(speed: 0.4).etaLabel, '400 kB/s');
    });

    test('speed-only and ETA-only each show independently', () {
      expect(_p(speed: 2.0).etaLabel, '2.0 MB/s');
      expect(
        _p(eta: const Duration(minutes: 2, seconds: 5)).etaLabel,
        '2:05 left',
      );
    });

    test('zero/negative sentinels are treated as unknown', () {
      expect(_p(speed: 0, eta: Duration.zero).etaLabel, isNull);
    });
  });
}
