// Contract tests for the ImageGenService surface, run over FakeImageGenService
// (no native code) so they execute on CI. Plus the pure-Dart PNG encoder.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dhruva/imagine_engine/fake_image_gen_service.dart';
import 'package:dhruva/imagine_engine/image_gen_service.dart';
import 'package:dhruva/imagine_engine/png_encoder.dart';
import 'package:dhruva/imagine_engine/sd_image_gen_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _p = ImageGenParams(
  prompt: 'a red apple',
  steps: 4,
  width: 64,
  height: 64,
);

bool _isPng(List<int> b) =>
    b.length > 8 &&
    b[0] == 0x89 &&
    b[1] == 0x50 &&
    b[2] == 0x4E &&
    b[3] == 0x47;

void main() {
  group('png_encoder', () {
    test('produces a valid, non-blank PNG with correct IHDR dims', () {
      final px = Uint8List(4 * 4 * 4);
      // A single white pixel so it is not uniformly blank.
      px[0] = 255;
      px[1] = 255;
      px[2] = 255;
      px[3] = 255;
      final png = encodePng(rgb: px, width: 4, height: 4, channels: 4);
      expect(_isPng(png), isTrue, reason: 'PNG magic');
      // IHDR width/height live at bytes 16..24 (after sig + len + "IHDR").
      final w = (png[16] << 24) | (png[17] << 16) | (png[18] << 8) | png[19];
      final h = (png[20] << 24) | (png[21] << 16) | (png[22] << 8) | png[23];
      expect(w, 4);
      expect(h, 4);
      expect(png.length, greaterThan(30));
    });

    test(
      'output decodes in a real PNG decoder (dart:ui) — CRCs correct',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        final px = Uint8List(12 * 10 * 3);
        for (var i = 0; i < px.length; i++) {
          px[i] = (i * 37) & 0xFF; // varied content, non-blank
        }
        final png = encodePng(rgb: px, width: 12, height: 10, channels: 3);
        // Skia rejects a PNG with a bad chunk CRC; a successful decode with the
        // right dimensions is the strict-decoder proof the encoder is correct.
        final codec = await ui.instantiateImageCodec(png);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 12);
        expect(frame.image.height, 10);
      },
    );

    test('rejects a too-small pixel buffer', () {
      expect(
        () => encodePng(rgb: Uint8List(4), width: 8, height: 8, channels: 3),
        throwsArgumentError,
      );
    });
  });

  group('FakeImageGenService contract', () {
    test('load → generate streams progress then a PNG result', () async {
      final svc = FakeImageGenService();
      await svc.loadModel('fake.safetensors');
      expect(svc.isLoaded, isTrue);

      final events = await svc.generate(_p).toList();
      final progress = events.whereType<ImageGenProgress>().toList();
      final results = events.whereType<ImageGenResult>().toList();
      expect(progress.length, 4);
      expect(progress.last.step, 4);
      expect(progress.last.totalSteps, 4);
      expect(results, hasLength(1));
      expect(_isPng(results.single.pngBytes), isTrue);
      await svc.dispose();
    });

    test(
      'cancel mid-stream terminates with ImageGenCancelled, no result',
      () async {
        final svc = FakeImageGenService(
          stepDelay: const Duration(milliseconds: 20),
        );
        await svc.loadModel('fake.safetensors');

        final events = <ImageGenEvent>[];
        final sub = svc.generate(_p).listen(events.add);
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await svc.cancel();
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await sub.cancel();

        expect(events.whereType<ImageGenResult>(), isEmpty);
        expect(events.whereType<ImageGenCancelled>(), isNotEmpty);
        await svc.dispose();
      },
    );

    test(
      'generate before load surfaces a disposed failure via the stream',
      () async {
        final svc = FakeImageGenService();
        await expectLater(
          svc.generate(_p),
          emitsError(isA<ImageGenDisposedFailure>()),
        );
      },
    );

    test(
      'a second concurrent generate is rejected as a state failure',
      () async {
        final svc = FakeImageGenService(
          stepDelay: const Duration(milliseconds: 20),
        );
        await svc.loadModel('fake.safetensors');
        final sub = svc.generate(_p).listen((_) {});
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await expectLater(
          svc.generate(_p),
          emitsError(isA<ImageGenStateFailure>()),
        );
        await sub.cancel();
        await svc.dispose();
      },
    );

    test('empty prompt / bad size are validation failures', () async {
      final svc = FakeImageGenService();
      await svc.loadModel('fake.safetensors');
      await expectLater(
        svc.generate(const ImageGenParams(prompt: '   ')),
        emitsError(isA<ImageGenValidationFailure>()),
      );
      await expectLater(
        svc.generate(const ImageGenParams(prompt: 'x', width: 100)),
        emitsError(isA<ImageGenValidationFailure>()),
      );
      await svc.dispose();
    });

    test(
      'loadFailure surfaces synchronously; unload resets isLoaded',
      () async {
        final svc = FakeImageGenService(
          loadFailure: const ImageGenLoadFailure('bad model'),
        );
        await expectLater(
          svc.loadModel('x'),
          throwsA(isA<ImageGenLoadFailure>()),
        );
        final ok = FakeImageGenService();
        await ok.loadModel('x');
        expect(ok.isLoaded, isTrue);
        await ok.unload();
        expect(ok.isLoaded, isFalse);
        expect(ok.unloadCount, 1);
      },
    );
  });

  group('SdImageGenService RAM gate (no native)', () {
    test('refuses to load while the LLM engine is resident', () async {
      // The one-heavy-model-at-a-time guard runs BEFORE any isolate/native
      // work, so it is testable without the sd.cpp dylib. Point it at a real
      // (empty) file so the existence check passes and the gate is what fires.
      final tmp = File(
        '${Directory.systemTemp.path}/dhruva_gate_${DateTime.now().microsecondsSinceEpoch}.safetensors',
      )..writeAsBytesSync(const [0]);
      addTearDown(() => tmp.deleteSync());

      final svc = SdImageGenService(isOtherHeavyModelResident: () => true);
      await expectLater(
        svc.loadModel(tmp.path),
        throwsA(isA<ImageGenStateFailure>()),
      );
      expect(svc.isLoaded, isFalse);
    });

    test('load rejects a missing model path with a load failure', () async {
      final svc = SdImageGenService();
      await expectLater(
        svc.loadModel('/no/such/model.safetensors'),
        throwsA(isA<ImageGenLoadFailure>()),
      );
    });
  });
}
