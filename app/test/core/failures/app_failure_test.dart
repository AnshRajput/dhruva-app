import 'package:dhruva/core/failures/app_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every failure carries its message and toString names the type', () {
    final failures = <AppFailure>[
      const NetworkOfflineFailure('offline'),
      const NetworkHttpFailure('http', statusCode: 500),
      const NetworkRateLimitFailure('rate limited'),
      const NetworkGatedFailure('gated'),
      const NetworkUnknownFailure('unknown'),
      const StorageInsufficientSpaceFailure(
        'no space',
        requiredBytes: 100,
        availableBytes: 10,
      ),
      const StorageIoFailure('io'),
      const StorageNotFoundFailure('not found'),
      const StorageCorruptFileFailure('corrupt'),
      const StorageUnknownFailure('unknown storage'),
      const ValidationFailure('bad input'),
      const UnknownFailure('last resort'),
    ];

    for (final failure in failures) {
      expect(failure.message, isNotEmpty);
      expect(failure.toString(), contains(failure.runtimeType.toString()));
      expect(failure.toString(), contains(failure.message));
    }
  });

  test('NetworkHttpFailure carries the status code', () {
    const failure = NetworkHttpFailure('server error', statusCode: 503);
    expect(failure.statusCode, 503);
  });

  test(
    'StorageInsufficientSpaceFailure carries required + available bytes',
    () {
      const failure = StorageInsufficientSpaceFailure(
        'no space',
        requiredBytes: 1000,
        availableBytes: 200,
      );
      expect(failure.requiredBytes, 1000);
      expect(failure.availableBytes, 200);
    },
  );

  test('cause is preserved when provided', () {
    final original = Exception('root cause');
    final failure = StorageIoFailure('wrapped', cause: original);
    expect(failure.cause, same(original));
  });
}
