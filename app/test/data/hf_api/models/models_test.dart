import 'package:dhruva/data/hf_api/models/hf_model_summary.dart';
import 'package:dhruva/data/hf_api/models/hf_repo_file.dart';
import 'package:dhruva/data/hf_api/models/model_license_info.dart';
import 'package:dhruva/data/hf_api/models/quant_variant.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HfRepoFile value equality + copyWith', () {
    const a = HfRepoFile(path: 'model.gguf', sizeBytes: 100, sha256: 'abc');
    const b = HfRepoFile(path: 'model.gguf', sizeBytes: 100, sha256: 'abc');
    expect(a, b);
    expect(a.copyWith(sizeBytes: 200).sizeBytes, 200);
  });

  test('QuantVariant wraps a file under a label', () {
    const file = HfRepoFile(path: 'model-Q4_K_M.gguf', sizeBytes: 100);
    const variant = QuantVariant(label: 'Q4_K_M', file: file);
    expect(variant.file.path, 'model-Q4_K_M.gguf');
  });

  test('ModelLicenseInfo.requiresAuth is true iff gated', () {
    const open = ModelLicenseInfo(
      license: 'apache-2.0',
      gatedStatus: HfGatedStatus.none,
    );
    const manual = ModelLicenseInfo(
      license: 'llama2',
      gatedStatus: HfGatedStatus.manual,
    );
    const auto = ModelLicenseInfo(
      license: 'other',
      gatedStatus: HfGatedStatus.auto,
    );
    expect(open.requiresAuth, isFalse);
    expect(manual.requiresAuth, isTrue);
    expect(auto.requiresAuth, isTrue);
  });

  test('HfModelSummary value equality', () {
    const license = ModelLicenseInfo(
      license: 'mit',
      gatedStatus: HfGatedStatus.none,
    );
    const a = HfModelSummary(
      id: 'org/model',
      likes: 1,
      downloads: 2,
      tags: ['gguf'],
      license: license,
    );
    const b = HfModelSummary(
      id: 'org/model',
      likes: 1,
      downloads: 2,
      tags: ['gguf'],
      license: license,
    );
    expect(a, b);
  });
}
