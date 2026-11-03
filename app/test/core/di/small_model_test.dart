import 'package:dhruva/core/di/small_model.dart';
import 'package:dhruva/data/downloads/storage_manager.dart';
import 'package:flutter_test/flutter_test.dart';

InstalledModelInfo _m(String repo, int bytes) => InstalledModelInfo(
  id: 1,
  repoId: repo,
  fileName: 'm.gguf',
  sizeBytes: bytes,
  localPath: '/tmp/m.gguf',
  gated: false,
  downloadedAt: DateTime.utc(2026),
  isVision: false,
);

void main() {
  const mb = 1024 * 1024;

  test('a 0.5B model by name is small, a 1B model is not', () {
    expect(isSmallModel(_m('Qwen/Qwen2.5-0.5B-Instruct-GGUF', 900 * mb)), true);
    expect(
      isSmallModel(_m('bartowski/Llama-3.2-1B-Instruct-GGUF', 800 * mb)),
      false,
    );
  });

  test('with no size in the name, a file under ~600 MB is small', () {
    expect(isSmallModel(_m('someone/Tiny-GGUF', 400 * mb)), true);
    expect(isSmallModel(_m('someone/Mid-GGUF', 2000 * mb)), false);
  });

  test('no model is not small', () {
    expect(isSmallModel(null), false);
  });
}
