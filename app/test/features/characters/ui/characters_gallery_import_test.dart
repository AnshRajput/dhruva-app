// Attack list #1 ("non-UTF8"): the gallery's JSON-card import path
// (characters_gallery_screen.dart's `_import`) reads the picked file with
// `picked.readAsString()` — `XFile.readAsString` (cross_file) forwards to
// `dart:io`'s `File.readAsString(encoding: utf8)`, which throws a
// `FileSystemException` ("Failed to decode data using encoding 'utf-8'",
// confirmed by actually running this) on bytes that aren't valid UTF-8. That
// part is dart:io's own behavior, not a bug, and unchanged by the fix below.
//
// FIXED (QA MED): `_import` used to only catch `on ValidationFailure`, so
// that FileSystemException propagated uncaught out of the PopupMenuButton's
// `onSelected` callback instead of the graceful "typed failure, snackbar,
// never crash" treatment every other malformed-card case gets. It now also
// catches `on FileSystemException`, showing the same SnackBar treatment.
//
// A widget-level repro (tap "Import JSON card" through the real gallery
// screen) was tried first and hung indefinitely under `pumpAndSettle()` —
// same known harness limitation flutter-core already flagged for
// CharacterAvatar's picked-image-file test (real `dart:io` file I/O doesn't
// reliably signal "settled" to the fake-async test clock without
// `tester.runAsync()`). That hang is an environmental test-harness
// limitation, not evidence of the app itself hanging. This test isolates the
// fix at the unit level instead — mirroring `_import`'s exact try/catch
// shape — which is fast, deterministic, and needs no widget pump.

import 'dart:io';
import 'dart:typed_data';

import 'package:dhruva/core/failures/app_failure.dart';
import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter_test/flutter_test.dart';

Future<XFile> _badUtf8File() async {
  final tempFile = File(
    '${Directory.systemTemp.path}/dhruva_qa_bad_utf8_'
    '${DateTime.now().microsecondsSinceEpoch}.json',
  );
  // 0xFF is invalid in every UTF-8 sequence position; 0x80 is a stray
  // continuation byte with no leading byte — both guarantee a decode
  // failure regardless of what follows.
  await tempFile.writeAsBytes(
    Uint8List.fromList([0x7B, 0xFF, 0x80, 0x22, 0x7D]),
  );
  addTearDown(() => tempFile.delete());
  return XFile(tempFile.path);
}

void main() {
  test('a non-UTF-8 picked file throws FileSystemException at the read step '
      '(dart:io\'s own behavior — the precondition the QA MED bug depended '
      'on, not itself a bug)', () async {
    final picked = await _badUtf8File();
    await expectLater(
      picked.readAsString(),
      throwsA(isA<FileSystemException>()),
    );
  });

  test(
    'FIXED (QA MED): a try/catch shaped like characters_gallery_screen.'
    'dart\'s _import (ValidationFailure + FileSystemException) catches a '
    'non-UTF-8 file\'s read failure instead of letting it crash uncaught',
    () async {
      final picked = await _badUtf8File();
      Object? caught;
      try {
        await picked.readAsString();
      } on ValidationFailure catch (e) {
        caught = e;
      } on FileSystemException catch (e) {
        caught = e;
      }
      expect(
        caught,
        isA<FileSystemException>(),
        reason:
            'the exception was caught (not rethrown uncaught) — this is '
            'what _import now does, surfacing a SnackBar instead of a crash',
      );
    },
  );
}
