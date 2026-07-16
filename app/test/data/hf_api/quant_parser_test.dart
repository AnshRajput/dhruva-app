import 'package:dhruva/data/hf_api/quant_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractQuantVariant', () {
    final cases = <String, String?>{
      'Qwen2.5-1.5B-Instruct-Q4_K_M.gguf': 'Q4_K_M',
      'Qwen2.5-1.5B-Instruct-Q2_K.gguf': 'Q2_K',
      'Qwen2.5-1.5B-Instruct-Q3_K_M.gguf': 'Q3_K_M',
      'Qwen2.5-1.5B-Instruct-Q5_K_M.gguf': 'Q5_K_M',
      'Qwen2.5-1.5B-Instruct-Q6_K.gguf': 'Q6_K',
      'Qwen2.5-1.5B-Instruct-Q8_0.gguf': 'Q8_0',
      'Qwen2.5-1.5B-Instruct-f16.gguf': 'F16',
      'model-F32.gguf': 'F32',
      'model-bf16.gguf': 'BF16',
      'model-IQ3_M.gguf': 'IQ3_M',
      'model-iq2_xxs.gguf': 'IQ2_XXS',
      'model-IQ4_NL.gguf': 'IQ4_NL',
      'mmproj-Q8_0.gguf': 'Q8_0',
      'model-q4_0.gguf': 'Q4_0',
      'model-Q4_1.gguf': 'Q4_1',
      // no recognizable quant token.
      'README.md': null,
      'tokenizer.json': null,
      'config.json': null,
    };

    cases.forEach((fileName, expected) {
      test('$fileName -> $expected', () {
        expect(extractQuantVariant(fileName), expected);
      });
    });
  });
}
