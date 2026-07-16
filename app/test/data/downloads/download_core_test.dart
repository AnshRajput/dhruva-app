import 'dart:typed_data';

import 'package:dhruva/core/failures/app_failure.dart';
import 'package:dhruva/data/downloads/download_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('hasGgufMagic', () {
    test('true for the exact 4-byte "GGUF" magic', () {
      expect(hasGgufMagic([0x47, 0x47, 0x55, 0x46]), isTrue);
    });

    test('true when more bytes follow the magic', () {
      expect(hasGgufMagic([0x47, 0x47, 0x55, 0x46, 0x03, 0x00]), isTrue);
    });

    test('false for wrong bytes', () {
      expect(hasGgufMagic([0x00, 0x00, 0x00, 0x00]), isFalse);
    });

    test('false for a truncated header', () {
      expect(hasGgufMagic([0x47, 0x47]), isFalse);
    });

    test('false for an empty header', () {
      expect(hasGgufMagic([]), isFalse);
    });

    test('false for a near-miss (3 of 4 bytes match)', () {
      expect(hasGgufMagic([0x47, 0x47, 0x55, 0x00]), isFalse);
    });
  });

  group('verifyIntegrity', () {
    test('null (ok) when size matches and no checksum is known', () {
      expect(
        verifyIntegrity(expectedSizeBytes: 100, actualSizeBytes: 100),
        isNull,
      );
    });

    test('size mismatch is always caught, even with no checksum', () {
      final failure = verifyIntegrity(
        expectedSizeBytes: 100,
        actualSizeBytes: 99,
      );
      expect(failure, isA<StorageCorruptFileFailure>());
    });

    test('null (ok) when size and checksum both match', () {
      expect(
        verifyIntegrity(
          expectedSizeBytes: 100,
          actualSizeBytes: 100,
          expectedSha256: 'ABC123',
          actualSha256: 'abc123',
        ),
        isNull, // case-insensitive comparison
      );
    });

    test('checksum mismatch is caught even when size matches', () {
      final failure = verifyIntegrity(
        expectedSizeBytes: 100,
        actualSizeBytes: 100,
        expectedSha256: 'abc123',
        actualSha256: 'def456',
      );
      expect(failure, isA<StorageCorruptFileFailure>());
    });

    test('missing actual checksum (not computed) does not fail the check', () {
      expect(
        verifyIntegrity(
          expectedSizeBytes: 100,
          actualSizeBytes: 100,
          expectedSha256: 'abc123',
          actualSha256: null,
        ),
        isNull,
      );
    });
  });

  group('checkStorageGuard', () {
    test('null (ok) when free space comfortably covers the file + margin', () {
      expect(
        checkStorageGuard(
          requiredBytes: 1000,
          freeBytes: 1000 + 200 * 1024 * 1024 + 1,
        ),
        isNull,
      );
    });

    test('fails exactly at the margin boundary', () {
      const required = 1000;
      const margin = 200 * 1024 * 1024;
      final failure = checkStorageGuard(
        requiredBytes: required,
        freeBytes: required + margin - 1,
      );
      expect(failure, isA<StorageInsufficientSpaceFailure>());
    });

    test('succeeds exactly at the margin boundary', () {
      const required = 1000;
      const margin = 200 * 1024 * 1024;
      final failure = checkStorageGuard(
        requiredBytes: required,
        freeBytes: required + margin,
      );
      expect(failure, isNull);
    });

    test('reports required (with margin) and available bytes', () {
      final failure = checkStorageGuard(requiredBytes: 500, freeBytes: 100)!;
      expect(failure.requiredBytes, 500 + 200 * 1024 * 1024);
      expect(failure.availableBytes, 100);
    });

    test('a custom margin is honored', () {
      expect(
        checkStorageGuard(requiredBytes: 100, freeBytes: 150, marginBytes: 40),
        isNull,
      );
      expect(
        checkStorageGuard(requiredBytes: 100, freeBytes: 130, marginBytes: 40),
        isA<StorageInsufficientSpaceFailure>(),
      );
    });
  });

  group('sha256Hex', () {
    test('matches the known sha256 of the empty byte array', () {
      // sha256("") is a well-known constant.
      expect(
        sha256Hex(Uint8List(0)),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('matches the known sha256 of "abc"', () {
      expect(
        sha256Hex(Uint8List.fromList('abc'.codeUnits)),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });
  });
}
