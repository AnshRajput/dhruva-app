// Loop 7 D4: a large image is resized before it reaches the engine.
// Constructs a real PNG via dart:ui (a solid-color square, well over
// kVisionMaxDimension) rather than committing a large binary fixture.
//
// QA (Loop-7 TEST, attack 4 "image handling hostility"): hostile-input cases
// below — corrupt bytes, 0-byte, extreme aspect ratio, an 8000x8000 huge
// image, EXIF-rotated JPEG, and an animated GIF. `test/assets/exif_rotated.
// jpg` and `test/assets/animated.gif` are small fixtures generated with
// Pillow (not committed as opaque binaries — see the QA report for the
// generating script) specifically to exercise dart:ui's own JPEG-EXIF and
// multi-frame-GIF decode behavior, which this file's `downscaleImage`
// depends on but doesn't control.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dhruva/features/chat/state/image_downscale.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _solidPng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFF0000),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<({int width, int height})> _dimensionsOf(Uint8List bytes) async {
  final descriptor = await ui.ImageDescriptor.encoded(
    await ui.ImmutableBuffer.fromUint8List(bytes),
  );
  final dims = (width: descriptor.width, height: descriptor.height);
  descriptor.dispose();
  return dims;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a large square image is downscaled to the max dimension', () async {
    final large = await _solidPng(2000, 2000);
    final before = await _dimensionsOf(large);
    expect(before.width, 2000);

    final result = await downscaleImage(large);
    final after = await _dimensionsOf(result);

    expect(after.width, lessThanOrEqualTo(kVisionMaxDimension));
    expect(after.height, lessThanOrEqualTo(kVisionMaxDimension));
    expect(result.length, lessThan(large.length));
  });

  test('aspect ratio is preserved for a non-square image', () async {
    final wide = await _solidPng(3000, 1500); // 2:1
    final result = await downscaleImage(wide);
    final after = await _dimensionsOf(result);

    expect(after.width, kVisionMaxDimension);
    expect(after.height, closeTo(kVisionMaxDimension / 2, 1));
  });

  test('an already-small image is returned unchanged (no decode/re-encode '
      'round trip)', () async {
    final small = await _solidPng(200, 150);
    final result = await downscaleImage(small);

    expect(result, same(small));
  });

  test('a custom maxDimension is honored', () async {
    final large = await _solidPng(2000, 2000);
    final result = await downscaleImage(large, maxDimension: 256);
    final after = await _dimensionsOf(result);

    expect(after.width, lessThanOrEqualTo(256));
    expect(after.height, lessThanOrEqualTo(256));
  });

  // QA attack 4: an 8000x8000 photo (the size a modern phone camera can
  // actually produce) downscales cleanly and lands at/under the ceiling —
  // no OOM, no hang. `_solidPng` renders the frame in-process, so this test
  // itself vouches for the decode+resize path handling that pixel count.
  test(
    'an 8000x8000 image downscales to the ceiling without OOM/hang',
    () async {
      final huge = await _solidPng(8000, 8000);
      final result = await downscaleImage(huge);
      final after = await _dimensionsOf(result);

      expect(after.width, lessThanOrEqualTo(kVisionMaxDimension));
      expect(after.height, lessThanOrEqualTo(kVisionMaxDimension));
      expect(result.length, lessThan(huge.length));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('an extreme aspect ratio (very wide) still downscales to the ceiling '
      'on the long axis, preserving ratio on the short axis', () async {
    final sliver = await _solidPng(6000, 60); // 100:1
    final result = await downscaleImage(sliver);
    final after = await _dimensionsOf(result);

    expect(after.width, kVisionMaxDimension);
    expect(after.height, greaterThan(0));
    expect(after.height, lessThan(20)); // ~10px at 100:1, never zero
  });

  test('a corrupt (not-an-image) byte blob throws instead of silently '
      'producing garbage output — documents the exact failure so callers '
      'know what to catch', () async {
    final garbage = Uint8List.fromList(List.generate(200, (i) => i % 256));
    await expectLater(downscaleImage(garbage), throwsA(isA<Exception>()));
  });

  test('0-byte input throws the same way as other corrupt input', () async {
    await expectLater(downscaleImage(Uint8List(0)), throwsA(isA<Exception>()));
  });

  test(
    'a non-image file (e.g. a renamed .txt) throws the same as garbage bytes '
    '— renaming the extension does not change what dart:ui decodes',
    () async {
      final notAnImage = Uint8List.fromList(
        utf8.encode('this is plain text, not image bytes, just renamed'),
      );
      await expectLater(downscaleImage(notAnImage), throwsA(isA<Exception>()));
    },
  );

  test('QA MED FIXED: an animated GIF is now REJECTED, not passed through at '
      'full resolution. Skia ignores targetWidth/targetHeight for GIF bytes '
      '(the ceiling silently did nothing), and a still-image vision model has '
      'no use for an animated frame set, so downscaleImage throws '
      'UnsupportedImageFormat rather than handing a multi-MB full-res GIF to '
      'mtmd. The composer catches it and shows a clear message.', () async {
    final gif = File('test/assets/animated.gif').readAsBytesSync();
    final codec = await ui.instantiateImageCodec(gif);
    expect(codec.frameCount, greaterThan(1), reason: 'fixture is not animated');
    codec.dispose();

    await expectLater(
      downscaleImage(gif, maxDimension: 20),
      throwsA(isA<UnsupportedImageFormat>()),
    );
  });

  test(
    'QA MED FIXED at realistic scale: a 3000x3000 animated GIF is rejected '
    'before any decode (magic-byte check) — no full-res GIF ever reaches mtmd',
    () async {
      final gif = File('test/assets/animated_large.gif').readAsBytesSync();
      final before = await _dimensionsOf(gif);
      expect(before.width, 3000);
      await expectLater(
        downscaleImage(gif),
        throwsA(isA<UnsupportedImageFormat>()),
      );
    },
  );

  test('an EXIF-rotated JPEG (orientation tag 6, pixel buffer stored landscape '
      'but meant to display portrait) decodes ALREADY ROTATED — dart:ui/Skia '
      'applies the EXIF transform at decode time on this engine version, so '
      'downscaleImage sees the correctly-oriented image and needs no '
      'orientation math of its own. The image_downscale.dart doc now states '
      'this correctly (QA LOW: the stale "decoder does not read EXIF" comment '
      'was fixed).', () async {
    final jpeg = File('test/assets/exif_rotated.jpg').readAsBytesSync();
    // Raw pixel buffer is 120w x 80h landscape; EXIF orientation 6 asks
    // for a 90 CW rotation to display correctly -> 80w x 120h portrait.
    final decoded = await _dimensionsOf(jpeg);
    expect(
      decoded.width,
      80,
      reason:
          'expected dart:ui to report the EXIF-rotated (portrait) '
          'dimensions; got the raw landscape buffer instead — if this '
          'starts failing, the code comment is right after all and a '
          'real orientation-correction bug exists',
    );
    expect(decoded.height, 120);

    // downscaleImage doesn't choke on it either (it's already small
    // enough to be a no-op here, exercising the "unchanged" path with a
    // real EXIF-bearing JPEG rather than only PNGs).
    final result = await downscaleImage(jpeg);
    expect(result, same(jpeg));
  });
}
