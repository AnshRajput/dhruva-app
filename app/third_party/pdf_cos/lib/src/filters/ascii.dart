import 'dart:typed_data';

import '../exceptions.dart';
import '../lexer.dart';
import '../objects.dart';
import 'decode_budget.dart';
import 'filters.dart';

class AsciiHexFilter extends CosFilter {
  const AsciiHexFilter();

  @override
  Uint8List decode(Uint8List data, CosDictionary? params, DecodeBudget budget) {
    final stage = budget.stage(); // dhruva: bounded decode
    stage.add((data.length + 1) >> 1); // never more than 1 byte per 2 digits
    final out = BytesBuilder();
    int? pending;
    for (final b in data) {
      if (b == 0x3E) break; // > terminator
      if (CosLexer.isWhitespace(b)) continue;
      final d = CosLexer.hexDigit(b);
      if (d == null) {
        throw CosParseException('invalid character in ASCIIHexDecode data');
      }
      if (pending == null) {
        pending = d;
      } else {
        out.addByte((pending << 4) | d);
        pending = null;
      }
    }
    if (pending != null) out.addByte(pending << 4);
    return out.takeBytes();
  }
}

class Ascii85Filter extends CosFilter {
  const Ascii85Filter();

  @override
  Uint8List decode(Uint8List data, CosDictionary? params, DecodeBudget budget) {
    final stage = budget.stage(); // dhruva: bounded decode
    final out = BytesBuilder();
    final group = <int>[];
    for (final b in data) {
      if (CosLexer.isWhitespace(b)) continue;
      if (b == 0x7E) break; // ~> terminator
      if (b == 0x7A && group.isEmpty) {
        // z is shorthand for four zero bytes
        stage.add(4); // dhruva: bounded decode
        out.add(const [0, 0, 0, 0]);
        continue;
      }
      if (b < 0x21 || b > 0x75) {
        throw CosParseException('invalid character in ASCII85Decode data');
      }
      group.add(b - 0x21);
      if (group.length == 5) {
        stage.add(4); // dhruva: bounded decode
        _emit(out, group, 4);
        group.clear();
      }
    }
    if (group.isNotEmpty) {
      if (group.length == 1) {
        throw CosParseException('truncated ASCII85Decode data');
      }
      final missing = 5 - group.length;
      for (var i = 0; i < missing; i++) {
        group.add(84); // pad with 'u'
      }
      stage.add(4 - missing); // dhruva: bounded decode
      _emit(out, group, 4 - missing);
    }
    return out.takeBytes();
  }

  void _emit(BytesBuilder out, List<int> group, int count) {
    var value = 0;
    for (final digit in group) {
      value = value * 85 + digit;
    }
    final bytes = [
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];
    out.add(bytes.sublist(0, count));
  }
}
