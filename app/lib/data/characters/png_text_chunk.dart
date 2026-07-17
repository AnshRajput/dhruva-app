/// Minimal, pure-Dart PNG chunk reader/writer — just enough to embed and
/// extract a `tEXt`/`iTXt` chunk by keyword. This is the mechanism
/// SillyTavern-style character-card tooling uses to carry a JSON card
/// inside a PNG avatar (see `character_card.dart`). No image-decoding
/// dependency is pulled in: we never touch pixel data, only the chunk
/// framing (`length | type | data | crc32`) that wraps it.
library;

import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import '../../core/failures/app_failure.dart';

/// The 8-byte PNG file signature every valid file starts with.
const List<int> pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

/// A minimal valid 1x1 transparent PNG (67 bytes), used as a placeholder
/// avatar by [embedTextChunk]'s callers when no real avatar is supplied.
/// This is the well-known minimal-PNG constant used across the web for
/// exactly this purpose — signature + IHDR + a single-pixel IDAT + IEND.
final Uint8List placeholderPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

final class _PngChunk {
  final String type;
  final Uint8List data;
  const _PngChunk(this.type, this.data);
}

bool _hasSignature(Uint8List bytes) {
  if (bytes.length < pngSignature.length) return false;
  for (var i = 0; i < pngSignature.length; i++) {
    if (bytes[i] != pngSignature[i]) return false;
  }
  return true;
}

List<_PngChunk> _parseChunks(Uint8List bytes) {
  if (!_hasSignature(bytes)) {
    throw const FormatException('not a PNG file (bad 8-byte signature)');
  }
  final view = ByteData.sublistView(bytes);
  final chunks = <_PngChunk>[];
  var offset = pngSignature.length;
  while (offset < bytes.length) {
    if (offset + 8 > bytes.length) {
      throw const FormatException('truncated PNG chunk header');
    }
    final length = view.getUint32(offset, Endian.big);
    final type = ascii.decode(bytes.sublist(offset + 4, offset + 8));
    final dataStart = offset + 8;
    final dataEnd = dataStart + length;
    if (dataEnd + 4 > bytes.length) {
      throw const FormatException('truncated PNG chunk data/CRC');
    }
    chunks.add(_PngChunk(type, bytes.sublist(dataStart, dataEnd)));
    // ponytail: reader never verifies the CRC-32 it skips here — a
    // bit-corrupted chunk that still decodes as valid base64/JSON (e.g. a
    // damaged "chara" chunk) is silently accepted rather than rejected (QA
    // Loop-5 INFO/LOW). Deliberate: real-world PNG viewers don't reject
    // bad-CRC ancillary chunks either, and this reader already throws
    // FormatException/ValidationFailure on anything that fails to actually
    // decode — add a `crc32(...)` recheck here (the function already exists
    // below) if a corrupt-but-decodable chara chunk ever turns out to
    // matter in practice.
    offset = dataEnd + 4; // skip the trailing CRC; write side recomputes it.
    if (type == 'IEND') break;
  }
  return chunks;
}

Uint8List _buildPng(List<_PngChunk> chunks) {
  final out = BytesBuilder();
  out.add(pngSignature);
  for (final chunk in chunks) {
    final typeBytes = ascii.encode(chunk.type);
    final length = ByteData(4)..setUint32(0, chunk.data.length, Endian.big);
    final crcInput = Uint8List(typeBytes.length + chunk.data.length)
      ..setRange(0, typeBytes.length, typeBytes)
      ..setRange(
        typeBytes.length,
        typeBytes.length + chunk.data.length,
        chunk.data,
      );
    final crc = ByteData(4)..setUint32(0, crc32(crcInput), Endian.big);
    out.add(length.buffer.asUint8List());
    out.add(typeBytes);
    out.add(chunk.data);
    out.add(crc.buffer.asUint8List());
  }
  return out.toBytes();
}

/// The keyword of a `tEXt`/`iTXt` chunk's payload, or null if [chunk] isn't
/// one of those types or has no null separator.
String? _keywordOf(_PngChunk chunk) {
  if (chunk.type != 'tEXt' && chunk.type != 'iTXt') return null;
  final nullIdx = chunk.data.indexOf(0);
  if (nullIdx < 0) return null;
  return latin1.decode(chunk.data.sublist(0, nullIdx));
}

/// Embeds [text] as a `tEXt` chunk under [keyword], inserted immediately
/// before `IEND` (chunks are legal anywhere after `IHDR`; right before
/// `IEND` is the convention character-card tools use). Any existing
/// `tEXt`/`iTXt` chunk with the same [keyword] is replaced first, so
/// re-embedding is idempotent rather than accumulating duplicates.
Uint8List embedTextChunk(Uint8List png, String keyword, String text) {
  final chunks = _parseChunks(
    png,
  ).where((c) => _keywordOf(c) != keyword).toList();
  final iend = chunks.indexWhere((c) => c.type == 'IEND');
  if (iend < 0) {
    throw const FormatException('PNG has no IEND chunk');
  }
  final keywordBytes = latin1.encode(keyword);
  final textBytes = latin1.encode(text);
  final payload = Uint8List(keywordBytes.length + 1 + textBytes.length)
    ..setRange(0, keywordBytes.length, keywordBytes)
    ..[keywordBytes.length] = 0x00
    ..setRange(
      keywordBytes.length + 1,
      keywordBytes.length + 1 + textBytes.length,
      textBytes,
    );
  chunks.insert(iend, _PngChunk('tEXt', payload));
  return _buildPng(chunks);
}

/// Reads the text stored under [keyword] in a `tEXt` or `iTXt` chunk, or
/// null if [png] has none. `iTXt` payloads compressed with zlib
/// (compression flag `1`) are inflated via `dart:io`'s `ZLibDecoder` —
/// everything this codebase itself *writes* is an uncompressed `tEXt`
/// chunk, but external tools sometimes ship compressed `iTXt`, so the
/// reader tolerates both.
String? readTextChunk(Uint8List png, String keyword) {
  for (final chunk in _parseChunks(png)) {
    if (chunk.type == 'tEXt') {
      if (_keywordOf(chunk) != keyword) continue;
      final nullIdx = chunk.data.indexOf(0);
      return latin1.decode(chunk.data.sublist(nullIdx + 1));
    }
    if (chunk.type == 'iTXt') {
      final text = _readITxt(chunk.data, keyword);
      if (text != null) return text;
    }
  }
  return null;
}

String? _readITxt(Uint8List data, String keyword) {
  final keywordEnd = data.indexOf(0);
  if (keywordEnd < 0 || latin1.decode(data.sublist(0, keywordEnd)) != keyword) {
    return null;
  }
  // keyword \0 | compression_flag(1) | compression_method(1) |
  // language_tag \0 | translated_keyword \0 | text
  var offset = keywordEnd + 1;
  if (offset + 2 > data.length) return null;
  final compressionFlag = data[offset];
  offset += 2;
  final langEnd = data.indexOf(0, offset);
  if (langEnd < 0) return null;
  offset = langEnd + 1;
  final translatedEnd = data.indexOf(0, offset);
  if (translatedEnd < 0) return null;
  offset = translatedEnd + 1;
  final textBytes = data.sublist(offset);
  if (compressionFlag == 1) {
    return utf8.decode(_inflateBounded(textBytes));
  }
  return utf8.decode(textBytes);
}

/// A compressed iTXt chunk's declared/compressed size says nothing about
/// its inflated size — a zlib bomb (a few KB compressed -> gigabytes
/// decompressed) in an imported PNG is an untrusted-import trust-boundary
/// crash vector (reviewer finding, Loop 5). A character card's persona/
/// example dialogues are at most a few KB, so anything past this ceiling is
/// rejected outright.
const _maxInflatedTextBytes = 8 * 1024 * 1024;

/// Inflates [compressed] via `ZLibDecoder`'s *streaming* chunked-conversion
/// API (not `.convert(...)`, which buffers the entire output before
/// returning) — output arrives in bounded increments as the decoder
/// produces it, so [_BoundedSink] can abort the moment the running total
/// crosses [_maxInflatedTextBytes], throwing [ValidationFailure] before the
/// decoder is ever asked to allocate a buffer sized to the (attacker-
/// controlled) full inflated length.
Uint8List _inflateBounded(Uint8List compressed) {
  final sink = _BoundedSink(_maxInflatedTextBytes);
  final input = ZLibDecoder().startChunkedConversion(sink);
  input.add(compressed);
  input.close();
  return sink.bytes;
}

class _BoundedSink implements Sink<List<int>> {
  final int limit;
  final BytesBuilder _builder = BytesBuilder(copy: false);
  int _total = 0;

  _BoundedSink(this.limit);

  Uint8List get bytes => _builder.toBytes();

  @override
  void add(List<int> chunk) {
    _total += chunk.length;
    if (_total > limit) {
      throw const ValidationFailure('character card image text too large');
    }
    _builder.add(chunk);
  }

  @override
  void close() {}
}

/// CRC-32 (ISO-HDLC / zip / PNG's checksum) over [bytes]. Pure Dart,
/// bit-by-bit (not the table-driven variant) — this is the only place in
/// the codebase that needs a CRC32 (the `crypto` package only has sha/md5/
/// hmac), and PNG chunk payloads here are at most a few KB of card JSON, so
/// the slower algorithm is not worth a 256-entry lookup table.
int crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      final mask = -(crc & 1);
      crc = (crc >> 1) ^ (0xEDB88320 & mask);
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
