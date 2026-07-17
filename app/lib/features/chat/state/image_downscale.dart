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

/// Thrown by [downscaleImage] for an animated/GIF input. Skia's codec ignores
/// `targetWidth`/`targetHeight` for GIF, so the downscale ceiling silently
/// does nothing and a multi-MB full-res GIF would reach mtmd (QA MED, Loop 7).
/// A still-image vision model has no use for an animated frame set anyway, so
/// we reject rather than cap — the composer surfaces a clear message.
class UnsupportedImageFormat implements Exception {
  final String message;
  const UnsupportedImageFormat(this.message);
  @override
  String toString() => 'UnsupportedImageFormat: $message';
}

/// Downscales [bytes] (any format `dart:ui` can decode — mtmd auto-detects
/// PNG/JPEG/etc regardless) so neither dimension exceeds [maxDimension],
/// preserving aspect ratio. Returns [bytes] unchanged when already within
/// bounds — no need to burn a decode+re-encode round trip on a screenshot
/// that's already small. Always re-encodes as PNG (lossless) when resizing.
///
/// Throws [UnsupportedImageFormat] for a GIF (see that type's doc), and lets
/// `dart:ui`'s own decode errors (corrupt/truncated bytes) propagate to the
/// caller — the composer catches both and shows a "couldn't attach" message.
///
/// EXIF orientation: `dart:ui`'s image codec DOES apply the EXIF orientation
/// tag on decode (Skia bakes it in), so a rotated gallery import comes through
/// upright — no separate rotation pass is needed here.
Future<Uint8List> downscaleImage(
  Uint8List bytes, {
  int maxDimension = kVisionMaxDimension,
}) async {
  if (_isGif(bytes)) {
    throw const UnsupportedImageFormat('animated GIFs are not supported');
  }
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

/// GIF magic bytes: "GIF8" (covers both GIF87a and GIF89a).
bool _isGif(Uint8List bytes) =>
    bytes.length >= 4 &&
    bytes[0] == 0x47 &&
    bytes[1] == 0x49 &&
    bytes[2] == 0x46 &&
    bytes[3] == 0x38;
