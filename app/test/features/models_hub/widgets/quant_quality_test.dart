import 'package:dhruva/features/models_hub/widgets/quant_quality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classifyQuantQuality', () {
    test('Q2/Q3 and IQ variants read as lower quality', () {
      expect(classifyQuantQuality('Q2_K'), QuantQuality.lower);
      expect(classifyQuantQuality('Q3_K_M'), QuantQuality.lower);
      expect(classifyQuantQuality('IQ3_M'), QuantQuality.lower);
      expect(classifyQuantQuality('IQ2_XS'), QuantQuality.lower);
    });

    test('Q4 family is the balanced/recommended band', () {
      expect(classifyQuantQuality('Q4_K_M'), QuantQuality.balanced);
      expect(classifyQuantQuality('Q4_0'), QuantQuality.balanced);
      expect(classifyQuantQuality('IQ4_NL'), QuantQuality.balanced);
    });

    test('Q5/Q6 are higher quality, larger', () {
      expect(classifyQuantQuality('Q5_K_M'), QuantQuality.higher);
      expect(classifyQuantQuality('Q6_K'), QuantQuality.higher);
    });

    test('Q8 and float families are near-lossless', () {
      expect(classifyQuantQuality('Q8_0'), QuantQuality.nearLossless);
      expect(classifyQuantQuality('F16'), QuantQuality.nearLossless);
      expect(classifyQuantQuality('BF16'), QuantQuality.nearLossless);
      expect(classifyQuantQuality('F32'), QuantQuality.nearLossless);
    });

    test('unrecognized label falls back to balanced, not a scary band', () {
      expect(classifyQuantQuality('weird'), QuantQuality.balanced);
    });
  });

  test('each band carries chip label + a "what this means" blurb', () {
    for (final q in QuantQuality.values) {
      expect(q.label, isNotEmpty);
      expect(q.blurb, isNotEmpty);
    }
  });
}
