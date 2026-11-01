import 'dart:typed_data';

import '../exceptions.dart';
import '../objects.dart';
import 'decode_budget.dart';
import 'filters.dart';

/// LZWDecode (§7.4.4): TIFF-style LZW with 9–12 bit codes packed MSB-first,
/// optionally followed by a PNG/TIFF predictor.
///
/// dhruva: bounded decode - the dictionary is four fixed arrays of 4096
/// entries (prefix code, last byte, first byte, length), so a code costs no
/// allocation; output goes through one growing [DecodeBuffer]. Upstream kept
/// a fresh `Uint8List` per code and per literal emission.
class LzwFilter extends CosFilter {
  const LzwFilter();

  static const int _clearCode = 256;
  static const int _eodCode = 257;
  static const int _firstFree = 258;
  static const int _maxCode = 4095;

  @override
  Uint8List decode(Uint8List data, CosDictionary? params, DecodeBudget budget) {
    final stage = budget.stage(); // dhruva: bounded decode
    // /EarlyChange 1 (the default) bumps the code width one code early.
    var earlyChange = 1;
    final early = params?['EarlyChange'];
    if (early is CosInteger && early.value == 0) earlyChange = 0;

    final out = DecodeBuffer(stage, expected: data.length * 2);
    // Entry for code c >= 258 lives at index c; codes < 256 are implicit
    // single bytes. An entry is the expansion of `prefix[c]` plus `last[c]`.
    final prefix = Uint16List(_maxCode + 1);
    final last = Uint8List(_maxCode + 1);
    final first = Uint8List(_maxCode + 1);
    final length = Uint16List(_maxCode + 1);
    for (var c = 0; c < 256; c++) {
      last[c] = c;
      first[c] = c;
      length[c] = 1;
    }
    var next = _firstFree; // next code to define
    var codeWidth = 9;
    var previous = -1;

    var buffer = 0;
    var bitsInBuffer = 0;
    var position = 0;

    int? nextCode() {
      while (bitsInBuffer < codeWidth) {
        if (position >= data.length) return null;
        buffer = ((buffer << 8) | data[position++]) & 0xFFFFFF;
        bitsInBuffer += 8;
      }
      bitsInBuffer -= codeWidth;
      final code = (buffer >> bitsInBuffer) & ((1 << codeWidth) - 1);
      return code;
    }

    while (true) {
      final code = nextCode();
      if (code == null || code == _eodCode) break;
      if (code == _clearCode) {
        next = _firstFree;
        codeWidth = 9;
        previous = -1;
        continue;
      }
      if (code == next && previous >= 0 && next <= _maxCode) {
        // the one special case: code being defined by this very step
        prefix[next] = previous;
        last[next] = first[previous];
        first[next] = first[previous];
        length[next] = length[previous] + 1;
        next++;
      } else {
        if (code >= next && code >= _firstFree) {
          throw CosParseException(
            'LZWDecode: code referenced before it was defined',
          );
        }
        if (previous >= 0 && next <= _maxCode) {
          prefix[next] = previous;
          last[next] = first[code];
          first[next] = first[previous];
          length[next] = length[previous] + 1;
          next++;
        }
      }
      // Emit the expansion of [code] by walking its prefix chain backwards
      // into the reserved tail of the output buffer.
      final len = length[code];
      stage.add(len); // dhruva: bounded decode
      final at = out.reserve(len);
      final bytes = out.bytes;
      var c = code;
      for (var k = at + len - 1; k >= at; k--) {
        bytes[k] = last[c];
        c = prefix[c];
      }
      previous = code;
      if (codeWidth < 12 && next + earlyChange > (1 << codeWidth)) {
        codeWidth++;
      }
    }
    return applyPredictor(out.takeBytes(), params, budget);
  }
}
