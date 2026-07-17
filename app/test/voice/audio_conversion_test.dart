import 'dart:typed_data';

import 'package:dhruva/voice/audio_conversion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pcm16ToFloat32', () {
    test('maps signed 16-bit LE to [-1, 1]', () {
      final bytes = Uint8List.fromList([
        0x00, 0x00, // 0
        0xFF, 0x7F, // 32767 → ~+1
        0x00, 0x80, // -32768 → -1
        0x00, 0x40, // 16384 → +0.5
      ]);
      final f = pcm16ToFloat32(bytes);
      expect(f.length, 4);
      expect(f[0], 0.0);
      expect(f[1], closeTo(0.999969, 1e-4));
      expect(f[2], -1.0);
      expect(f[3], closeTo(0.5, 1e-6));
    });

    test('drops a trailing odd byte instead of misreading it', () {
      final f = pcm16ToFloat32(Uint8List.fromList([0x00, 0x40, 0x11]));
      expect(f.length, 1);
      expect(f[0], closeTo(0.5, 1e-6));
    });

    test('empty input → empty output', () {
      expect(pcm16ToFloat32(Uint8List(0)).length, 0);
    });
  });

  group('float32ToPcm16', () {
    test('round-trips within one quantization step', () {
      final original = Float32List.fromList([0.0, 0.5, -0.5, 0.25, -1.0]);
      final back = pcm16ToFloat32(float32ToPcm16(original));
      for (var i = 0; i < original.length; i++) {
        expect(back[i], closeTo(original[i], 1 / 32767));
      }
    });

    test('clamps out-of-range values instead of wrapping', () {
      final pcm = float32ToPcm16(Float32List.fromList([2.0, -2.0]));
      final view = ByteData.sublistView(pcm);
      expect(view.getInt16(0, Endian.little), 32767);
      expect(view.getInt16(2, Endian.little), -32767);
    });
  });

  group('floatSamplesToWav', () {
    test('writes a valid 44-byte PCM WAV header', () {
      final wav = floatSamplesToWav(Float32List.fromList([0.0, 0.5]), 16000);
      String ascii(int o, int n) => String.fromCharCodes(wav.sublist(o, o + n));
      expect(ascii(0, 4), 'RIFF');
      expect(ascii(8, 4), 'WAVE');
      expect(ascii(12, 4), 'fmt ');
      expect(ascii(36, 4), 'data');
      final head = ByteData.sublistView(wav);
      expect(head.getUint16(20, Endian.little), 1); // PCM
      expect(head.getUint16(22, Endian.little), 1); // mono
      expect(head.getUint32(24, Endian.little), 16000); // sample rate
      expect(head.getUint16(34, Endian.little), 16); // bits/sample
      expect(head.getUint32(40, Endian.little), 4); // 2 samples * 2 bytes
      expect(wav.length, 44 + 4);
    });
  });
}
