import 'package:dhruva/data/hf_api/mobile_suitability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('paramBillionsFromName', () {
    test('reads a plain param token', () {
      expect(paramBillionsFromName('bartowski/Llama-3.2-3B-Instruct-GGUF'), 3);
      expect(paramBillionsFromName('org/Qwen2.5-1.5B-Instruct-GGUF'), 1.5);
      expect(paramBillionsFromName('org/Model-70B-GGUF'), 70);
    });

    test('picks the largest token, not the version number', () {
      // "3.2" is a version (no B), "1B" is the param count.
      expect(paramBillionsFromName('org/Llama-3.2-1B-GGUF'), 1);
    });

    test('expands an MoE NxM token to total experts', () {
      expect(paramBillionsFromName('org/Mixtral-8x7B-GGUF'), 56);
    });

    test('returns null when no size token is present', () {
      expect(paramBillionsFromName('org/SomeCoolModel-GGUF'), isNull);
    });

    // QA (Phase B attack #4): the exact repo-id shapes named in the attack
    // brief, verbatim.
    test('Llama-3.2-70B: the 70B param token, not the 3.2 version', () {
      expect(
        paramBillionsFromName('bartowski/Llama-3.2-70B-Instruct-GGUF'),
        70,
      );
    });

    test('Qwen2.5-1.5B: 1.5B param token, "Qwen2.5" alone never matches', () {
      expect(
        paramBillionsFromName('bartowski/Qwen2.5-1.5B-Instruct-GGUF'),
        1.5,
      );
      // The exact ask: a bare version-looking number with no repo-wide B
      // token anywhere must NOT be misread as a param count.
      expect(paramBillionsFromName('bartowski/Qwen2.5-GGUF'), isNull);
    });

    test('Mixtral-8x7B: MoE token resolves to 56 (8 * 7)', () {
      expect(paramBillionsFromName('mistralai/Mixtral-8x7B-Instruct-GGUF'), 56);
    });

    test(
      'SmolLM2-1.7B: the "2" in SmolLM2 is not mistaken for a param count',
      () {
        expect(
          paramBillionsFromName('bartowski/SmolLM2-1.7B-Instruct-GGUF'),
          1.7,
        );
      },
    );

    test('no-number name returns null', () {
      expect(paramBillionsFromName('TheBloke/NoNumbersHere-GGUF'), isNull);
    });
  });

  group('mobileSuitabilityOf', () {
    test('small models are friendly', () {
      expect(mobileSuitabilityOf('o/Llama-3.2-1B'), MobileSuitability.friendly);
      expect(mobileSuitabilityOf('o/Model-4B'), MobileSuitability.friendly);
    });
    test('big models are heavy', () {
      expect(mobileSuitabilityOf('o/Model-70B'), MobileSuitability.heavy);
      expect(mobileSuitabilityOf('o/Model-34B'), MobileSuitability.heavy);
    });
    test('mid-size and unknown are neutral', () {
      expect(mobileSuitabilityOf('o/Model-7B'), MobileSuitability.neutral);
      expect(mobileSuitabilityOf('o/MysteryModel'), MobileSuitability.neutral);
    });

    // QA (Phase B attack #4): the exact named cases end-to-end through the
    // bucketing function, not just the parser.
    test('Llama-3.2-70B sinks (heavy)', () {
      expect(
        mobileSuitabilityOf('bartowski/Llama-3.2-70B-Instruct-GGUF'),
        MobileSuitability.heavy,
      );
    });
    test('Qwen2.5-1.5B floats (friendly)', () {
      expect(
        mobileSuitabilityOf('bartowski/Qwen2.5-1.5B-Instruct-GGUF'),
        MobileSuitability.friendly,
      );
    });
    test('Mixtral-8x7B (MoE, 56B effective) sinks (heavy)', () {
      expect(
        mobileSuitabilityOf('mistralai/Mixtral-8x7B-Instruct-GGUF'),
        MobileSuitability.heavy,
      );
    });
    test('SmolLM2-1.7B floats (friendly)', () {
      expect(
        mobileSuitabilityOf('bartowski/SmolLM2-1.7B-Instruct-GGUF'),
        MobileSuitability.friendly,
      );
    });
  });

  group('filterMobileRunnable (WS1 strict ≤ ~4B advanced-search filter)', () {
    test('drops known > 4B, keeps ≤ 4B and unknown-size repos', () {
      final input = [
        'org/Model-70B-GGUF', // heavy — dropped
        'org/Model-8B-GGUF', // > 4B — dropped
        'org/Model-4B-GGUF', // exactly 4B — kept
        'org/Tiny-1B-GGUF', // kept
        'org/MysteryModel-GGUF', // unknown size — kept
        'org/Mixtral-8x7B-GGUF', // 56B MoE — dropped
      ];
      expect(filterMobileRunnable(input, (s) => s), [
        'org/Model-4B-GGUF',
        'org/Tiny-1B-GGUF',
        'org/MysteryModel-GGUF',
      ]);
    });

    test('empty when every model is too large', () {
      expect(
        filterMobileRunnable(['a/70B-GGUF', 'b/13B-GGUF'], (s) => s),
        isEmpty,
      );
    });
  });

  test(
    'rankByMobileSuitability floats small up, sinks large, stable middle',
    () {
      final input = [
        'org/Model-70B-GGUF', // heavy
        'org/Popular-Unknown-GGUF', // neutral (first neutral)
        'org/Tiny-1B-GGUF', // friendly
        'org/Another-Unknown-GGUF', // neutral (second neutral)
        'org/Small-3B-GGUF', // friendly
      ];
      final ranked = rankByMobileSuitability(input, (s) => s);
      expect(ranked, [
        'org/Tiny-1B-GGUF', // friendly, original order
        'org/Small-3B-GGUF',
        'org/Popular-Unknown-GGUF', // neutral, stable
        'org/Another-Unknown-GGUF',
        'org/Model-70B-GGUF', // heavy last
      ]);
    },
  );
}
