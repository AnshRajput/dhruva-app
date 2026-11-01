// The PDF extraction watchdog limit scales with device RAM:
// min(350 MB, 12% of RAM), floor 150 MB.

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/data/docs/document_extractor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _gb = 1024 * 1024 * 1024;
const _mb = 1024 * 1024;

void main() {
  group('extractionRssLimitFor', () {
    test('big phones keep the 350 MB ceiling', () {
      expect(extractionRssLimitFor(8 * _gb), maxExtractionRssGrowth);
      expect(extractionRssLimitFor(3 * _gb), maxExtractionRssGrowth);
    });

    test('mid phones get 12% of RAM', () {
      expect(extractionRssLimitFor(2 * _gb), (2 * _gb * 0.12).floor());
      expect(extractionRssLimitFor(2 * _gb), lessThan(350 * _mb));
      expect(extractionRssLimitFor(2 * _gb), greaterThan(150 * _mb));
    });

    test('small phones are floored at 150 MB', () {
      expect(extractionRssLimitFor(1 * _gb), 150 * _mb);
      expect(extractionRssLimitFor(512 * _mb), 150 * _mb);
    });

    test('unknown RAM keeps the ceiling', () {
      expect(extractionRssLimitFor(0), maxExtractionRssGrowth);
    });
  });

  test('documentExtractorProvider builds with a device-info override', () {
    final c = ProviderContainer(
      overrides: [
        deviceInfoServiceProvider.overrideWithValue(
          const FakeDeviceInfoService(
            memory: DeviceMemoryInfo(totalBytes: _gb, availableBytes: _gb),
            storage: DeviceStorageInfo(totalBytes: _gb, freeBytes: _gb),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    expect(c.read(documentExtractorProvider), isNotNull);
  });
}
