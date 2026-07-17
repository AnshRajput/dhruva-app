/// Minimal, dependency-free PNG encoder for raw 8-bit RGB/RGBA buffers.
///
/// sd.cpp hands back a raw pixel buffer (`sd_image_t.data`, channel = 3 or 4);
/// the UI wants a real image file. Rather than pull in the `image` package for
/// one encode, we build a spec-correct PNG here: IHDR + a single zlib-deflated
/// IDAT (via `dart:io`'s ZLibCodec — available on mobile/desktop, not web,
/// which is fine since this only runs on the native worker isolate) + IEND,
/// each chunk CRC32-checked.
///
/// ponytail: no filtering (every scanline uses filter type 0) — smaller code,
/// slightly larger file; zlib still compresses well. Add adaptive filtering if
/// output size ever matters.
library;

import 'dart:io';
import 'dart:typed_data';

/// Encode [rgb] (`width*height*channels` bytes, row-major, top-to-bottom) as a
/// PNG. [channels] must be 3 (RGB) or 4 (RGBA). Returns the complete PNG file.
Uint8List encodePng({
  required Uint8List rgb,
  required int width,
  required int height,
  required int channels,
}) {
  if (channels != 3 && channels != 4) {
    throw ArgumentError('channels must be 3 (RGB) or 4 (RGBA), got $channels');
  }
  final expected = width * height * channels;
  if (rgb.length < expected) {
    throw ArgumentError(
      'pixel buffer too small: ${rgb.length} < $expected '
      '($width x $height x $channels)',
    );
  }

  // Raw image data: each scanline prefixed with a filter byte (0 = None).
  final stride = width * channels;
  final raw = Uint8List((stride + 1) * height);
  var dst = 0;
  var src = 0;
  for (var y = 0; y < height; y++) {
    raw[dst++] = 0; // filter type: None
    raw.setRange(dst, dst + stride, rgb, src);
    dst += stride;
    src += stride;
  }

  final idatData = Uint8List.fromList(zlib.encode(raw));

  final out = BytesBuilder(copy: false);
  // PNG signature.
  out.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

  // IHDR.
  final ihdr = Uint8List(13);
  final ihdrView = ByteData.view(ihdr.buffer);
  ihdrView.setUint32(0, width);
  ihdrView.setUint32(4, height);
  ihdr[8] = 8; // bit depth
  ihdr[9] = channels == 4 ? 6 : 2; // color type: RGBA=6, RGB=2
  ihdr[10] = 0; // compression
  ihdr[11] = 0; // filter
  ihdr[12] = 0; // interlace
  _writeChunk(out, 'IHDR', ihdr);

  _writeChunk(out, 'IDAT', idatData);
  _writeChunk(out, 'IEND', Uint8List(0));

  return out.toBytes();
}

void _writeChunk(BytesBuilder out, String type, Uint8List data) {
  final typeBytes = Uint8List.fromList(type.codeUnits);
  final len = Uint8List(4);
  ByteData.view(len.buffer).setUint32(0, data.length);
  out.add(len);
  out.add(typeBytes);
  out.add(data);
  // CRC32 runs over type THEN data, in that order (seed 0xFFFFFFFF, final XOR).
  final crc = _crc32(data, _crc32(typeBytes, 0xFFFFFFFF)) ^ 0xFFFFFFFF;
  final crcBytes = Uint8List(4);
  ByteData.view(crcBytes.buffer).setUint32(0, crc);
  out.add(crcBytes);
}

// CRC32 is computed over type+data; we fold both in via the running accumulator
// (seeded 0xFFFFFFFF, final XOR applied by the caller). Table built once.
final Uint32List _crcTable = _buildCrcTable();

Uint32List _buildCrcTable() {
  final t = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    t[n] = c;
  }
  return t;
}

int _crc32(Uint8List data, int crc) {
  var c = crc;
  for (var i = 0; i < data.length; i++) {
    c = _crcTable[(c ^ data[i]) & 0xFF] ^ (c >> 8);
  }
  return c & 0xFFFFFFFF;
}
