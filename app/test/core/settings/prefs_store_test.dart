// M5: preference writes are atomic (temp file + rename), so a kill mid-write
// never resets every preference.

import 'dart:io';

import 'package:dhruva/core/settings/prefs_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('dhruva_prefs'));
  tearDown(() => dir.deleteSync(recursive: true));

  File main0() => File(p.join(dir.path, 'app_prefs_v1.json'));
  File tmp() => File('${main0().path}.tmp');

  test('a write leaves one whole file and no temp behind', () async {
    final s = FilePrefsStore(dir);
    await s.write('a', '1');
    await s.write('b', '2');
    expect(tmp().existsSync(), isFalse);
    expect(await FilePrefsStore(dir).read('a'), '1');
    expect(await FilePrefsStore(dir).read('b'), '2');
  });

  test(
    'a crash mid-write (truncated temp, old file intact) loses nothing',
    () async {
      final s = FilePrefsStore(dir);
      await s.write('hide_in_app_switcher', 'true');
      // The process died while writing the next version: the temp is cut off,
      // the real file was never touched.
      tmp().writeAsStringSync('{"hide_in_app_switcher":"tr');
      final again = FilePrefsStore(dir);
      expect(await again.read('hide_in_app_switcher'), 'true');
      await again.write('other', 'x'); // and the next write still works
      expect(await again.read('hide_in_app_switcher'), 'true');
      expect(await again.read('other'), 'x');
    },
  );

  test('a crash after the temp was fully written but before the rename is '
      'recovered from the temp', () async {
    main0().writeAsStringSync(
      '{"a":"old"',
    ); // corrupt (older, non-atomic write)
    tmp().writeAsStringSync('{"a":"new"}');
    expect(await FilePrefsStore(dir).read('a'), 'new');
  });

  test(
    'a corrupt file with no temp still reads as empty, then recovers',
    () async {
      main0().writeAsStringSync('not json');
      final s = FilePrefsStore(dir);
      expect(await s.read('a'), isNull);
      await s.write('a', '1');
      expect(await s.read('a'), '1');
    },
  );
}
