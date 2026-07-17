/// Pure PCM conversions between the `record` mic stream (16-bit signed
/// little-endian PCM) and the normalized float32 sherpa wants. Kept separate
/// from the platform adapters so this logic is unit-tested (the adapters aren't
/// runnable under `flutter test`).
library;

import 'dart:typed_data';

/// Convert little-endian signed 16-bit PCM [bytes] to float32 in [-1, 1].
///
/// A trailing odd byte (a half-sample from a chunk boundary) is dropped rather
/// than misread — the next chunk carries its other half.
Float32List pcm16ToFloat32(Uint8List bytes) {
  final sampleCount = bytes.length ~/ 2;
  final out = Float32List(sampleCount);
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < sampleCount; i++) {
    final s = view.getInt16(i * 2, Endian.little);
    // -32768 maps to -1.0 exactly; divide by 32768 so the range is symmetric.
    out[i] = s / 32768.0;
  }
  return out;
}

/// Inverse of [pcm16ToFloat32]: float32 in [-1, 1] to LE signed 16-bit PCM.
/// Values are clamped so an out-of-range sample can't wrap around.
Uint8List float32ToPcm16(Float32List samples) {
  final out = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    final clamped = samples[i].clamp(-1.0, 1.0);
    final s = (clamped * 32767.0).round();
    out.setInt16(i * 2, s, Endian.little);
  }
  return out.buffer.asUint8List();
}

/// Wrap normalized mono float32 [samples] at [sampleRate] in a 16-bit PCM WAV
/// container. Handy for handing synthesized audio to a file/byte player without
/// a native `writeWave` round-trip.
Uint8List floatSamplesToWav(Float32List samples, int sampleRate) {
  final pcm = float32ToPcm16(samples);
  final header = ByteData(44);
  final dataLen = pcm.length;
  void writeAscii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      header.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  writeAscii(0, 'RIFF');
  header.setUint32(4, 36 + dataLen, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little); // PCM fmt chunk size
  header.setUint16(20, 1, Endian.little); // audio format = PCM
  header.setUint16(22, 1, Endian.little); // mono
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 2, Endian.little); // byte rate (mono/16bit)
  header.setUint16(32, 2, Endian.little); // block align
  header.setUint16(34, 16, Endian.little); // bits per sample
  writeAscii(36, 'data');
  header.setUint32(40, dataLen, Endian.little);

  final out = Uint8List(44 + dataLen);
  out.setAll(0, header.buffer.asUint8List());
  out.setAll(44, pcm);
  return out;
}
