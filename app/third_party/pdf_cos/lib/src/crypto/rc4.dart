import 'dart:typed_data';

/// RC4 stream cipher, as used by PDF security handlers up to revision 4
/// (§7.6.2). Encryption and decryption are the same operation.
Uint8List rc4(List<int> key, Uint8List data) {
  final s = Uint8List(256);
  for (var i = 0; i < 256; i++) {
    s[i] = i;
  }
  var j = 0;
  for (var i = 0; i < 256; i++) {
    j = (j + s[i] + key[i % key.length]) & 0xFF;
    final t = s[i];
    s[i] = s[j];
    s[j] = t;
  }
  final out = Uint8List(data.length);
  var i = 0;
  j = 0;
  for (var k = 0; k < data.length; k++) {
    i = (i + 1) & 0xFF;
    j = (j + s[i]) & 0xFF;
    final t = s[i];
    s[i] = s[j];
    s[j] = t;
    out[k] = data[k] ^ s[(s[i] + s[j]) & 0xFF];
  }
  return out;
}
