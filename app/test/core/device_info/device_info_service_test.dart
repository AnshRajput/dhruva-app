import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'FakeDeviceInfoService returns the fixed readings it was given',
    () async {
      const memory = DeviceMemoryInfo(
        totalBytes: 4000000000,
        availableBytes: 1500000000,
      );
      const storage = DeviceStorageInfo(
        totalBytes: 64000000000,
        freeBytes: 8000000000,
      );
      const service = FakeDeviceInfoService(memory: memory, storage: storage);

      expect(await service.getMemoryInfo(), same(memory));
      expect(await service.getStorageInfo(), same(storage));
    },
  );
}
