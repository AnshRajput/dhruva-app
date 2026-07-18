import 'package:dhruva/core/failures/app_failure.dart';
import 'package:dhruva/core/failures/failure_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('friendlyFailureMessage', () {
    test('offline', () {
      expect(
        friendlyFailureMessage(const NetworkOfflineFailure('x')),
        contains("You're offline"),
      );
    });

    test('rate limit', () {
      expect(
        friendlyFailureMessage(const NetworkRateLimitFailure('x')),
        contains('rate-limiting'),
      );
    });

    test('gated', () {
      expect(
        friendlyFailureMessage(const NetworkGatedFailure('x')),
        contains('Dhruva'),
      );
    });

    test('http error includes the status code', () {
      expect(
        friendlyFailureMessage(const NetworkHttpFailure('x', statusCode: 503)),
        contains('503'),
      );
    });

    test('network unknown', () {
      expect(
        friendlyFailureMessage(const NetworkUnknownFailure('x')),
        contains("Couldn't read"),
      );
    });

    test('insufficient space formats GB', () {
      final msg = friendlyFailureMessage(
        const StorageInsufficientSpaceFailure(
          'x',
          requiredBytes: 2 * 1024 * 1024 * 1024,
          availableBytes: 512 * 1024 * 1024,
        ),
      );
      expect(msg, contains('2.0 GB'));
      expect(msg, contains('512 MB'));
    });

    test('corrupt file', () {
      expect(
        friendlyFailureMessage(const StorageCorruptFileFailure('x')),
        contains('integrity check'),
      );
    });

    test('not found', () {
      expect(
        friendlyFailureMessage(const StorageNotFoundFailure('x')),
        contains('no longer available'),
      );
    });

    test('storage io', () {
      expect(
        friendlyFailureMessage(const StorageIoFailure('x')),
        'A storage error occurred.',
      );
    });

    test('storage unknown', () {
      expect(
        friendlyFailureMessage(const StorageUnknownFailure('x')),
        'A storage error occurred.',
      );
    });

    test('validation passes the message through', () {
      expect(
        friendlyFailureMessage(const ValidationFailure('bad input')),
        'bad input',
      );
    });

    test('unknown', () {
      expect(
        friendlyFailureMessage(const UnknownFailure('x')),
        'Something went wrong.',
      );
    });
  });

  group('describeError', () {
    test('AppFailure gets its typed message', () {
      expect(
        describeError(const NetworkOfflineFailure('x')),
        contains("You're offline"),
      );
    });

    test('non-AppFailure falls back to a generic message', () {
      expect(describeError(Exception('boom')), 'Something went wrong.');
    });
  });
}
