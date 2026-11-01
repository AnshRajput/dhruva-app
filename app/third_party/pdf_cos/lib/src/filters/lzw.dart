import 'dart:typed_data';

import '../exceptions.dart';
import '../objects.dart';
import 'decode_budget.dart';
import 'filters.dart';

/// LZWDecode (§7.4.4): TIFF-style LZW with 9–12 bit codes packed MSB-first,
/// optionally followed by a PNG/TIFF predictor.
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

    final out = BytesBuilder(copy: false);
    // table[i] for i < 256 is implicit (single byte i); entries hold the
    // expanded byte sequences for codes >= 258
    var table = <Uint8List>[];
    var codeWidth = 9;
    Uint8List? previous;

    var buffer = 0;
    var bitsInBuffer = 0;
    var position = 0;

    int? nextCode() {
      while (bitsInBuffer < codeWidth) {
        if (position >= data.length) return null;
        buffer = (buffer << 8) | data[position++];
        bitsInBuffer += 8;
      }
      bitsInBuffer -= codeWidth;
      final code = (buffer >> bitsInBuffer) & ((1 << codeWidth) - 1);
      return code;
    }

    Uint8List entryFor(int code) {
      if (code < 256) return Uint8List.fromList([code]);
      final index = code - _firstFree;
      if (index >= table.length) {
        throw CosParseException(
            'LZWDecode: code referenced before it was defined');
      }
      return table[index];
    }

    while (true) {
      final code = nextCode();
      if (code == null || code == _eodCode) break;
      if (code == _clearCode) {
        table = [];
        codeWidth = 9;
        previous = null;
        continue;
      }
      Uint8List sequence;
      if (code - _firstFree == table.length && previous != null) {
        // the one special case: code being defined by this very step
        sequence = Uint8List(previous.length + 1)
          ..setRange(0, previous.length, previous)
          ..[previous.length] = previous[0];
      } else {
        sequence = entryFor(code);
      }
      stage.add(sequence.length); // dhruva: bounded decode
      out.add(sequence);
      if (previous != null && _firstFree + table.length <= _maxCode) {
        final entry = Uint8List(previous.length + 1)
          ..setRange(0, previous.length, previous)
          ..[previous.length] = sequence[0];
        table.add(entry);
      }
      previous = sequence;
      final next = _firstFree + table.length;
      if (codeWidth < 12 && next + earlyChange > (1 << codeWidth)) {
        codeWidth++;
      }
    }
    return applyPredictor(out.takeBytes(), params, budget);
  }
}
