import 'package:dhruva/data/hf_api/default_quant.dart';
import 'package:dhruva/data/hf_api/models/hf_repo_file.dart';
import 'package:dhruva/data/hf_api/models/quant_variant.dart';
import 'package:flutter_test/flutter_test.dart';

QuantVariant _q(String label, String path, int size) => QuantVariant(
  label: label,
  file: HfRepoFile(path: path, sizeBytes: size),
);

void main() {
  test('prefers an exact Q4_K_M even when smaller quants exist', () {
    final pick = pickDefaultQuant([
      _q('IQ2_XXS', 'm-IQ2_XXS.gguf', 500),
      _q('Q4_K_M', 'm-Q4_K_M.gguf', 1000),
      _q('Q8_0', 'm-Q8_0.gguf', 2000),
    ]);
    expect(pick!.label, 'Q4_K_M');
  });

  test('falls back to the smallest Q4-family file when no exact Q4_K_M', () {
    final pick = pickDefaultQuant([
      _q('Q4_K_S', 'm-Q4_K_S.gguf', 900),
      _q('Q4_0', 'm-Q4_0.gguf', 850),
      _q('Q8_0', 'm-Q8_0.gguf', 2000),
    ]);
    expect(pick!.label, 'Q4_0'); // smallest Q4
  });

  test('falls back to the smallest file overall when no Q4 at all', () {
    final pick = pickDefaultQuant([
      _q('Q8_0', 'm-Q8_0.gguf', 2000),
      _q('Q5_K_M', 'm-Q5_K_M.gguf', 1500),
    ]);
    expect(pick!.label, 'Q5_K_M');
  });

  test('skips mmproj projector files', () {
    final pick = pickDefaultQuant([
      _q('Q8_0', 'mmproj-Q8_0.gguf', 100), // smallest, but a projector
      _q('Q4_K_M', 'model-Q4_K_M.gguf', 1000),
    ]);
    expect(pick!.file.path, 'model-Q4_K_M.gguf');
  });

  test('returns null when only projector files are present', () {
    expect(pickDefaultQuant([_q('Q8_0', 'mmproj-Q8_0.gguf', 100)]), isNull);
    expect(pickDefaultQuant(const []), isNull);
  });

  // QA (Phase B attack #1), NOW FIXED: a repo with an imatrix/duplicate
  // Q4_K_M in a subfolder alongside the root one. The pick must be the
  // SMALLEST matching file, deterministically, regardless of the file-tree
  // order HF returned them in.
  test('two Q4_K_M files: picks the SMALLEST deterministically, independent '
      'of list order', () {
    final rootFirst = pickDefaultQuant([
      _q('Q4_K_M', 'model-Q4_K_M.gguf', 900), // root, smaller
      _q('Q4_K_M', 'imatrix/model-Q4_K_M.gguf', 4000), // subfolder, bigger
    ]);
    expect(rootFirst!.file.path, 'model-Q4_K_M.gguf');
    expect(rootFirst.file.sizeBytes, 900);

    // Flip the order — the pick is stable: still the smaller file.
    final subfolderFirst = pickDefaultQuant([
      _q('Q4_K_M', 'imatrix/model-Q4_K_M.gguf', 4000),
      _q('Q4_K_M', 'model-Q4_K_M.gguf', 900),
    ]);
    expect(subfolderFirst!.file.path, 'model-Q4_K_M.gguf');
    expect(subfolderFirst.file.sizeBytes, 900);
  });
}
