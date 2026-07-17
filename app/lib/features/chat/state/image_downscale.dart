/// Client-side downscale for images attached to a vision chat turn (Loop 7).
/// Vision models want ~512-1024px input, and mtmd re-encodes whatever's
/// handed to it anyway — shrinking an oversized photo before it reaches the
/// engine keeps prompt-encode memory sane (a 12MP camera photo is ~15x more
/// pixels than the model needs) and keeps the attach flow snappy.
///
/// `dart:ui`'s own codec does the decode+resize (ladder rung 4 — a native
/// platform feature, no `image`-processing package needed): `targetWidth`/
/// `targetHeight` on `ImageDescriptor.instantiateCodec` scale while
/// preserving aspect ratio when only one axis is given.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

/// mtmd/vision-model target resolution (chat-spec.md vision addendum,
/// orchestra/BLACKBOARD.md LOOP-07 PLAN: "vision models want ~512-1024px").
const kVisionMaxDimension = 1024;

/// Downscales [bytes] (any format `dart:ui` can decode — mtmd auto-detects
/// PNG/JPEG/etc regardless) so neither dimension exceeds [maxDimension],
/// preserving aspect ratio. Returns [bytes] unchanged when already within
/// bounds — no need to burn a decode+re-encode round trip on a screenshot
/// that's already small. Always re-encodes as PNG (lossless) when resizing.
///
/// ponytail: EXIF orientation is not corrected here — `dart:ui`'s decoder
/// doesn't read the EXIF tag, so a rotated gallery import could render
/// sideways. Camera captures on iOS/Android are typically already upright
/// (rotation baked in by the OS camera pipeline). Upgrade path if QA repros
/// a sideways image: bake orientation with `package:image` before this
/// function runs.
Future<Uint8List> downscaleImage(
  Uint8List bytes, {
  int maxDimension = kVisionMaxDimension,
}) async {
  final descriptor = await ui.ImageDescriptor.encoded(
    await ui.ImmutableBuffer.fromUint8List(bytes),
  );
  final width = descriptor.width;
  final height = descriptor.height;
  if (width <= maxDimension && height <= maxDimension) {
    descriptor.dispose();
    return bytes;
  }

  descriptor.dispose();
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: width >= height ? maxDimension : null,
    targetHeight: height > width ? maxDimension : null,
  );
  final frame = await codec.getNextFrame();
  codec.dispose();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  frame.image.dispose();
  return data!.buffer.asUint8List();
}
