import 'package:dhruva/data/downloads/storage_manager.dart';
import 'package:dhruva/features/chat/state/lighter_model.dart';
import 'package:flutter_test/flutter_test.dart';

InstalledModelInfo _m(int id, int size) => InstalledModelInfo(
  id: id,
  repoId: 'r/$id',
  fileName: '$id.gguf',
  sizeBytes: size,
  localPath: '/m/$id',
  gated: false,
  downloadedAt: DateTime.utc(2026),
);

void main() {
  test('picks the smallest installed model that is smaller than current', () {
    final big = _m(1, 4000);
    final mid = _m(2, 2000);
    final small = _m(3, 800);
    expect(lighterModel([big, mid, small], big)?.id, 3);
    expect(lighterModel([big, mid, small], mid)?.id, 3);
  });

  test('null when the current model is already the smallest', () {
    final small = _m(3, 800);
    expect(lighterModel([_m(1, 4000), small], small), isNull);
    expect(lighterModel([small], small), isNull);
    expect(lighterModel(const [], small), isNull);
  });

  test('equal-size models are not "lighter"', () {
    expect(lighterModel([_m(1, 1000), _m(2, 1000)], _m(1, 1000)), isNull);
  });

  test('no current model: the smallest installed one', () {
    expect(lighterModel([_m(1, 4000), _m(2, 800)], null)?.id, 2);
  });
}
