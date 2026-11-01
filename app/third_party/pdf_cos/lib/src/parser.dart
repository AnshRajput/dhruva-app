import 'dart:typed_data';

import 'exceptions.dart';
import 'lexer.dart';
import 'objects.dart';
import 'token.dart';

/// Resolves an indirect reference to its object. The parser needs this when a
/// stream's /Length is itself an indirect reference.
typedef CosResolver = CosObject Function(CosReference ref);

/// Parses COS objects from a byte buffer.
class CosParser {
  CosParser(Uint8List bytes, {int offset = 0, CosResolver? resolver})
      : _lexer = CosLexer(bytes, offset),
        _resolver = resolver;

  final CosLexer _lexer;
  final CosResolver? _resolver;
  final List<CosToken> _lookahead = [];

  Uint8List get bytes => _lexer.bytes;

  CosToken peekToken([int n = 0]) {
    while (_lookahead.length <= n) {
      _lookahead.add(_lexer.nextToken());
    }
    return _lookahead[n];
  }

  CosToken nextToken() =>
      _lookahead.isNotEmpty ? _lookahead.removeAt(0) : _lexer.nextToken();

  /// Discards lookahead and continues lexing from [position].
  void seek(int position) {
    _lookahead.clear();
    _lexer.position = position;
  }

  CosToken expectKeyword(String keyword) {
    final t = nextToken();
    if (!t.isKeyword(keyword)) {
      throw CosParseException('expected "$keyword", found $t', t.offset);
    }
    return t;
  }

  int expectInteger() {
    final t = nextToken();
    if (t.type != CosTokenType.integer) {
      throw CosParseException('expected integer, found $t', t.offset);
    }
    return t.intValue;
  }

  /// Parses one object: a direct value, a reference, or a stream.
  CosObject parseObject() {
    final t = peekToken();
    switch (t.type) {
      case CosTokenType.integer:
        // `N G R` is a reference; a bare integer is just an integer.
        if (peekToken(1).type == CosTokenType.integer &&
            peekToken(2).isKeyword('R')) {
          final number = nextToken().intValue;
          final generation = nextToken().intValue;
          nextToken(); // R
          return CosReference(number, generation);
        }
        nextToken();
        return CosInteger(t.intValue);
      case CosTokenType.real:
        nextToken();
        return CosReal(t.realValue);
      case CosTokenType.string:
        nextToken();
        return CosString(t.bytesValue);
      case CosTokenType.hexString:
        nextToken();
        return CosString(t.bytesValue, isHex: true);
      case CosTokenType.name:
        nextToken();
        return CosName(t.textValue);
      case CosTokenType.arrayOpen:
        return _parseArray();
      case CosTokenType.dictOpen:
        return _parseDictionaryOrStream();
      case CosTokenType.keyword:
        nextToken();
        switch (t.textValue) {
          case 'true':
            return const CosBoolean(true);
          case 'false':
            return const CosBoolean(false);
          case 'null':
            return CosNull.instance;
        }
        throw CosParseException(
            'unexpected keyword "${t.textValue}"', t.offset);
      case CosTokenType.eof:
        throw CosParseException('unexpected end of input', t.offset);
      case CosTokenType.arrayClose:
      case CosTokenType.dictClose:
        throw CosParseException('unexpected token $t', t.offset);
    }
  }

  /// Parses `N G obj ... endobj`. A missing `endobj` is tolerated.
  CosIndirectObject parseIndirectObject() {
    final number = expectInteger();
    final generation = expectInteger();
    expectKeyword('obj');
    final object = parseObject();
    if (peekToken().isKeyword('endobj')) {
      nextToken();
    }
    return CosIndirectObject(number, generation, object);
  }

  CosArray _parseArray() {
    nextToken(); // [
    final items = <CosObject>[];
    while (true) {
      final t = peekToken();
      if (t.type == CosTokenType.arrayClose) {
        nextToken();
        break;
      }
      if (t.type == CosTokenType.eof) {
        throw CosParseException('unterminated array', t.offset);
      }
      items.add(parseObject());
    }
    return CosArray(items);
  }

  CosObject _parseDictionaryOrStream() {
    nextToken(); // <<
    final dict = CosDictionary();
    while (true) {
      final t = peekToken();
      if (t.type == CosTokenType.dictClose) {
        nextToken();
        break;
      }
      if (t.type == CosTokenType.eof) {
        throw CosParseException('unterminated dictionary', t.offset);
      }
      if (t.type != CosTokenType.name) {
        throw CosParseException(
            'expected name as dictionary key, found $t', t.offset);
      }
      nextToken();
      dict[t.textValue] = parseObject();
    }
    if (peekToken().isKeyword('stream')) {
      return _parseStream(dict);
    }
    return dict;
  }

  CosStream _parseStream(CosDictionary dict) {
    final streamToken = nextToken();
    seek(streamToken.offset + 'stream'.length);
    _lexer.skipEol();
    final dataStart = _lexer.position;

    // Trust /Length only if "endstream" actually follows it; real-world
    // writers get it wrong, in which case we scan for the marker instead.
    var length = _resolveLength(dict['Length']);
    if (length != null && !_endstreamFollows(dataStart + length)) {
      length = null;
    }
    length ??= _scanForEndstream(dataStart);

    final data = Uint8List.sublistView(bytes, dataStart, dataStart + length);
    seek(dataStart + length);
    expectKeyword('endstream');
    return CosStream(dict, data);
  }

  int? _resolveLength(CosObject? lengthObject) {
    var obj = lengthObject;
    if (obj is CosReference) {
      final resolver = _resolver;
      if (resolver == null) return null;
      obj = resolver(obj);
    }
    if (obj is CosInteger && obj.value >= 0) return obj.value;
    return null;
  }

  bool _endstreamFollows(int position) {
    if (position < 0 || position > bytes.length) return false;
    var p = position;
    while (p < bytes.length && CosLexer.isWhitespace(bytes[p])) {
      p++;
    }
    return _matchesAt(p, 'endstream');
  }

  bool _matchesAt(int position, String word) {
    if (position + word.length > bytes.length) return false;
    for (var i = 0; i < word.length; i++) {
      if (bytes[position + i] != word.codeUnitAt(i)) return false;
    }
    return true;
  }

  int _scanForEndstream(int dataStart) {
    for (var p = dataStart; p + 'endstream'.length <= bytes.length; p++) {
      if (bytes[p] == 0x65 /* e */ && _matchesAt(p, 'endstream')) {
        var end = p;
        // the EOL before "endstream" separates, it is not stream data
        if (end > dataStart && bytes[end - 1] == 0x0A) end--;
        if (end > dataStart && bytes[end - 1] == 0x0D) end--;
        return end - dataStart;
      }
    }
    throw CosParseException('missing "endstream"', dataStart);
  }
}
