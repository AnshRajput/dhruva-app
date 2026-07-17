import 'package:dhruva/core/failures/app_failure.dart';
import 'package:dhruva/data/chat/models/sampling_params.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults match documented llama.cpp-style values', () {
    const params = SamplingParams();
    expect(params.temperature, 0.8);
    expect(params.topP, 0.95);
    expect(params.topK, 40);
    expect(params.contextLength, 4096);
    expect(params.maxTokens, 512);
    expect(params.seed, isNull);
  });

  test('toJson / fromJson round-trips every field', () {
    const params = SamplingParams(
      temperature: 1.1,
      topP: 0.8,
      topK: 20,
      contextLength: 8192,
      maxTokens: 1024,
      seed: 42,
    );
    final restored = SamplingParams.fromJson(params.toJson());
    expect(restored, params);
  });

  test('toJson omits seed when null; fromJson defaults it back to null', () {
    const params = SamplingParams();
    expect(params.toJson().containsKey('seed'), isFalse);
    expect(SamplingParams.fromJson(params.toJson()).seed, isNull);
  });

  test('fromJson fills missing keys with defaults', () {
    final restored = SamplingParams.fromJson(const {'temperature': 0.5});
    expect(restored.temperature, 0.5);
    expect(restored.topP, 0.95);
    expect(restored.topK, 40);
  });

  group('validate', () {
    test('accepts the defaults', () {
      expect(() => const SamplingParams().validate(), returnsNormally);
    });

    test('rejects out-of-range temperature', () {
      expect(
        () => const SamplingParams(temperature: 2.5).validate(),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        () => const SamplingParams(temperature: -0.1).validate(),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('rejects out-of-range topP', () {
      expect(
        () => const SamplingParams(topP: 1.5).validate(),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('rejects negative topK', () {
      expect(
        () => const SamplingParams(topK: -1).validate(),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('rejects non-positive contextLength', () {
      expect(
        () => const SamplingParams(contextLength: 0).validate(),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('rejects maxTokens greater than contextLength', () {
      expect(
        () => const SamplingParams(
          contextLength: 512,
          maxTokens: 1024,
        ).validate(),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('rejects a negative or too-large seed', () {
      expect(
        () => const SamplingParams(seed: -1).validate(),
        throwsA(isA<ValidationFailure>()),
      );
      expect(
        () => const SamplingParams(seed: 4294967296).validate(),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('accepts a valid seed', () {
      expect(
        () => const SamplingParams(seed: 12345).validate(),
        returnsNormally,
      );
    });
  });
}
