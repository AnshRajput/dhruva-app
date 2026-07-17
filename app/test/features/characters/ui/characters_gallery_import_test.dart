// Attack list #1 ("non-UTF8"): the gallery's JSON-card import path
// (characters_gallery_screen.dart's `_import`) reads the picked file with
// `picked.readAsString()` — `XFile.readAsString` (cross_file) forwards to
// `dart:io`'s `File.readAsString(encoding: utf8)`, which throws a
// `FileSystemException` ("Failed to decode data using encoding 'utf-8'",
// confirmed by actually running this) on bytes that aren't valid UTF-8.
// `_import` only catches `on ValidationFailure catch (e)` around the whole
// parse, so that FileSystemException is NOT caught — it propagates uncaught
// out of the
// PopupMenuButton's `onSelected` callback instead of the graceful
// "typed failure, snackbar, never crash" behavior every other malformed-
// import case in this codebase gets.
//
// A widget-level repro (tap "Import JSON card" through the real gallery
// screen) was tried first and hung indefinitely under `pumpAndSettle()` —
// same known harness limitation flutter-core already flagged for
// CharacterAvatar's picked-image-file test (real `dart:io` file I/O doesn't
// reliably signal "settled" to the fake-async test clock without
// `tester.runAsync()`). That hang is an environmental test-harness
// limitation, not evidence of the app itself hanging. This test isolates
// the actual bug — the uncaught FormatException — at the unit level
// instead, which is fast, deterministic, and needs no widget pump.

import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BUG (MED) repro: characters_gallery_screen.dart\'s import path reads a '
      'picked JSON file via `XFile.readAsString()`, which throws a '
      'FileSystemException (not a ValidationFailure) on non-UTF-8 bytes — '
      '`_import`\'s `on ValidationFailure catch (e)` (characters_gallery_'
      'screen.dart, around the try block wrapping `CharacterCardV2.parse('
      'await picked.readAsString())`) does not catch this, so it crashes '
      'uncaught instead of surfacing the same graceful SnackBar every other '
      'malformed-card-import case gets. Fix: either catch FileSystemException '
      'alongside ValidationFailure in `_import`, or read bytes and decode '
      'with `utf8.decode(bytes, allowMalformed: true)` (or a try/catch '
      'around the decode step) so this path surfaces a ValidationFailure '
      'like every sibling malformed-card case already does.', () async {
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

    // Exactly what `_import` does: `picked.readAsString()` on the XFile
    // the file picker handed back.
    final picked = XFile(tempFile.path);
    await expectLater(
      picked.readAsString(),
      throwsA(isA<FileSystemException>()),
      reason:
          'this is the CURRENT (buggy) behavior — a FileSystemException, '
          'which is NOT a ValidationFailure and so is not caught by '
          "_import's `on ValidationFailure` clause. Once fixed (either "
          'catching FileSystemException too, or decoding leniently), this '
          'assertion should change to confirm a ValidationFailure instead.',
    );
  });
}
