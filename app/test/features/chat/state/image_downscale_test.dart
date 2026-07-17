// Loop 7 D4: a large image is resized before it reaches the engine.
// Constructs a real PNG via dart:ui (a solid-color square, well over
// kVisionMaxDimension) rather than committing a large binary fixture.

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
}
