import 'package:dhruva/data/downloads/download_manager.dart';
import 'package:flutter_test/flutter_test.dart';

DownloadProgress _p({
  double speed = -1,
  Duration eta = const Duration(seconds: -1),
  int downloaded = 1,
  int? total = 10,
}) => DownloadProgress(
  taskId: 't',
  repoId: 'r',
  fileName: 'f',
  state: DownloadState.running,
  downloadedBytes: downloaded,
  totalBytes: total,
  networkSpeedMBs: speed,
  timeRemaining: eta,
);

const _mb = 1024 * 1024;

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

  group('DownloadProgress.transferLabel (bytes + speed + ETA, honest)', () {
    test('bytes only when speed/ETA unknown', () {
      expect(
        _p(downloaded: 128 * _mb, total: 512 * _mb).transferLabel,
        '128 MB / 512 MB',
      );
    });

    test('full line: bytes · speed · ETA', () {
      expect(
        _p(
          downloaded: 128 * _mb,
          total: 512 * _mb,
          speed: 3.14,
          eta: const Duration(seconds: 45),
        ).transferLabel,
        '128 MB / 512 MB · 3.1 MB/s · 0:45 left',
      );
    });

    test('null (renders nothing) when total unknown and no estimate', () {
      expect(_p(total: null).transferLabel, isNull);
    });

    test('speed/ETA still show when total is unknown', () {
      expect(_p(total: null, speed: 2.0).transferLabel, '2.0 MB/s');
    });
  });

  group('formatDownloadBytes', () {
    test('scales B / kB / MB / GB', () {
      expect(formatDownloadBytes(512), '512 B');
      expect(formatDownloadBytes(2 * 1024), '2 kB');
      expect(formatDownloadBytes(512 * _mb), '512 MB');
      expect(formatDownloadBytes(3 * 1024 * _mb), '3.00 GB');
    });
  });
}
