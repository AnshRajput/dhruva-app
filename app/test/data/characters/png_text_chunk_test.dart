import 'dart:convert';
import 'dart:typed_data';

import 'package:dhruva/data/characters/png_text_chunk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('crc32', () {
    test(
      'matches the standard CRC-32 (ISO-HDLC) check value for "123456789"',
      () {
        // The canonical test vector for this exact polynomial/variant (the
        // same one PNG/zip/gzip use) — see the CRC-32 Catalogue's "check"
        // value. Confirms our bit-by-bit implementation is the right
        // polynomial/reflection/xor-out combination, independent of any
        // round-trip test below.
        expect(crc32(ascii.encode('123456789')), 0xCBF43926);
      },
    );

    test('CRC32 of empty input is 0', () {
      expect(crc32(const []), 0);
    });
  });

  group('placeholderPng', () {
    test('starts with the PNG signature', () {
      expect(placeholderPng.sublist(0, 8), pngSignature);
    });

    test('has no "chara" chunk yet', () {
      expect(readTextChunk(placeholderPng, 'chara'), isNull);
    });
  });

  group('embedTextChunk / readTextChunk round-trip', () {
    test('embeds and reads back a short ascii payload', () {
      final embedded = embedTextChunk(placeholderPng, 'chara', 'hello world');
      expect(embedded.sublist(0, 8), pngSignature);
      expect(readTextChunk(embedded, 'chara'), 'hello world');
    });

    test('embeds and reads back a realistic base64-JSON payload', () {
      final payload = base64Encode(
        utf8.encode(jsonEncode({'name': 'Coach', 'greeting': 'Hi!'})),
      );
      final embedded = embedTextChunk(placeholderPng, 'chara', payload);
      final extracted = readTextChunk(embedded, 'chara');
      expect(extracted, payload);
      expect(jsonDecode(utf8.decode(base64Decode(extracted!))), {
        'name': 'Coach',
        'greeting': 'Hi!',
      });
    });

    test('re-embedding the same keyword replaces, not duplicates', () {
      final first = embedTextChunk(placeholderPng, 'chara', 'v1');
      final second = embedTextChunk(first, 'chara', 'v2');
      expect(readTextChunk(second, 'chara'), 'v2');
      // Only one 'chara' tEXt chunk should exist — a naive "just append"
      // implementation would still return 'v2' here (first match wins) but
      // would leave a stale 'v1' chunk bloating the file; assert the byte
      // count reflects a genuine replace, not an append.
      final onlyV2 = embedTextChunk(placeholderPng, 'chara', 'v2');
      expect(second.length, onlyV2.length);
    });

    test('a different keyword is independent', () {
      final embedded = embedTextChunk(placeholderPng, 'chara', 'card-data');
      final withSecond = embedTextChunk(embedded, 'other', 'other-data');
      expect(readTextChunk(withSecond, 'chara'), 'card-data');
      expect(readTextChunk(withSecond, 'other'), 'other-data');
    });

    test('every chunk CRC in the written PNG is correct', () {
      final embedded = embedTextChunk(placeholderPng, 'chara', 'payload');
      var offset = 8;
      final view = ByteData.sublistView(embedded);
      while (offset < embedded.length) {
        final length = view.getUint32(offset, Endian.big);
        final typeAndData = embedded.sublist(offset + 4, offset + 8 + length);
        final storedCrc = view.getUint32(offset + 8 + length, Endian.big);
        expect(
          crc32(typeAndData),
          storedCrc,
          reason: 'chunk at offset $offset',
        );
        offset += 8 + length + 4;
        final type = ascii.decode(typeAndData.sublist(0, 4));
        if (type == 'IEND') break;
      }
    });
  });

  group('readTextChunk on a real iTXt chunk (uncompressed)', () {
    test('parses keyword/lang/translated-keyword/text framing', () {
      // Hand-built iTXt chunk: keyword\0 compression(0) method(0) lang\0
      // translated\0 utf8-text. Verifies our reader against the iTXt
      // structure directly (not just our own tEXt writer).
      final builder = BytesBuilder();
      builder.add(ascii.encode('chara'));
      builder.addByte(0); // null after keyword
      builder.addByte(0); // compression flag: uncompressed
      builder.addByte(0); // compression method
      builder.addByte(0); // empty language tag + its null terminator
      builder.addByte(0); // empty translated keyword + its null terminator
      builder.add(utf8.encode('itxt-payload'));
      final itxtData = builder.toBytes();

      final png = _pngWithRawChunk('iTXt', itxtData);
      expect(readTextChunk(png, 'chara'), 'itxt-payload');
    });
  });

  group('malformed PNG input', () {
    test('bad signature throws FormatException', () {
      expect(
        () => readTextChunk(Uint8List.fromList([1, 2, 3, 4]), 'chara'),
        throwsFormatException,
      );
    });

    test('truncated chunk header throws FormatException', () {
      final truncated = placeholderPng.sublist(0, 10);
      expect(() => readTextChunk(truncated, 'chara'), throwsFormatException);
    });

    test('embedding into a PNG with no IEND throws FormatException', () {
      final noIend = _pngWithRawChunk(
        'IHDR',
        Uint8List(13),
        includeIend: false,
      );
      expect(() => embedTextChunk(noIend, 'chara', 'x'), throwsFormatException);
    });
  });
}

/// Builds a minimal PNG containing exactly one chunk of [type]/[data]
/// (plus IEND unless [type] already is IEND), correctly CRC'd — for tests
/// that need to hand-construct chunk framing rather than round-trip
/// through [embedTextChunk].
Uint8List _pngWithRawChunk(
  String type,
  Uint8List data, {
  bool includeIend = true,
}) {
  final out = BytesBuilder();
  out.add(pngSignature);
  void writeChunk(String t, List<int> d) {
    final typeBytes = ascii.encode(t);
    final length = ByteData(4)..setUint32(0, d.length, Endian.big);
    final crcInput = Uint8List.fromList([...typeBytes, ...d]);
    final crc = ByteData(4)..setUint32(0, crc32(crcInput), Endian.big);
    out.add(length.buffer.asUint8List());
    out.add(typeBytes);
    out.add(d);
    out.add(crc.buffer.asUint8List());
  }

  writeChunk(type, data);
  if (includeIend && type != 'IEND') writeChunk('IEND', const []);
  return out.toBytes();
}
