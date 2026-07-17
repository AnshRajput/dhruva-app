// Real image generation THROUGH the ImageGenService abstraction (not the CLI),
// on macOS with the vendored sd.cpp dylib + an SD 1.5 checkpoint. Skips when
// the native artifacts are absent (CI / other machines), keeping `make verify`
// green without a 4 GB model.
//
// Proves D4 (real image out of the abstraction) and D3 (the free path: a
// load→unload→reload cycle does not grow RSS by ~one model each time — if
// free_sd_ctx were skipped, the multi-GB context would leak per cycle).

import 'dart:io';

import 'package:dhruva/imagine_engine/image_gen_service.dart';
import 'package:dhruva/imagine_engine/sd_image_gen_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../native_test_config.dart';

bool _isPng(List<int> b) =>
    b.length > 8 &&
    b[0] == 0x89 &&
    b[1] == 0x50 &&
    b[2] == 0x4E &&
    b[3] == 0x47 &&
    b[4] == 0x0D &&
    b[5] == 0x0A &&
    b[6] == 0x1A &&
    b[7] == 0x0A;

void main() {
  final paths = resolveSdPaths();
  final skip = paths == null
      ? 'native sd.cpp artifacts absent (dylib and/or model)'
      : false;

  test(
    'generates a real, valid, non-blank PNG through the abstraction',
    () async {
      final svc = SdImageGenService(libraryPath: paths!.libraryPath);
      addTearDown(svc.dispose);

      await svc.loadModel(paths.modelPath);
      expect(svc.isLoaded, isTrue);

      final progress = <ImageGenProgress>[];
      ImageGenResult? result;
      await for (final e in svc.generate(
        const ImageGenParams(
          prompt: 'a red apple on a wooden table',
          steps: 6,
          width: 384,
          height: 384,
          cfgScale: 7,
          seed: 42,
        ),
      )) {
        if (e is ImageGenProgress) progress.add(e);
        if (e is ImageGenResult) result = e;
      }

      expect(result, isNotNull, reason: 'no image produced');
      final r = result!;
      // Valid PNG signature.
      expect(_isPng(r.pngBytes), isTrue, reason: 'not a valid PNG');
      expect(r.width, 384);
      expect(r.height, 384);
      // A blank/failed frame compresses to a few hundred bytes; a real 384²
      // image is tens of KB. Guards against an all-black/empty result.
      expect(
        r.pngBytes.length,
        greaterThan(20 * 1024),
        reason: 'PNG suspiciously small — likely a blank frame',
      );
      // Progress callback fired at least once per requested step region.
      expect(progress, isNotEmpty, reason: 'no progress ticks');

      // Write it out so a human can eyeball the evidence.
      final out = File(
        '${Directory.systemTemp.path}/dhruva_sd_real_${DateTime.now().millisecondsSinceEpoch}.png',
      )..writeAsBytesSync(r.pngBytes);
      // ignore: avoid_print
      print(
        'REAL GEN: ${r.width}x${r.height}, ${r.pngBytes.length} bytes, '
        '${r.elapsedMs}ms, ${progress.length} progress ticks -> ${out.path}',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
    skip: skip,
  );

  test(
    'load/unload/reload frees the ctx (RSS does not grow unboundedly)',
    () async {
      final svc = SdImageGenService(libraryPath: paths!.libraryPath);
      addTearDown(svc.dispose);

      const cycles = 3;
      final rss = <int>[];
      for (var i = 0; i < cycles; i++) {
        await svc.loadModel(paths.modelPath);
        expect(svc.isLoaded, isTrue, reason: 'load failed on cycle $i');

        // A minimal generation to exercise the full path each cycle.
        await for (final _ in svc.generate(
          const ImageGenParams(
            prompt: 'a red apple',
            steps: 1,
            width: 256,
            height: 256,
            seed: 1,
          ),
        )) {}

        await svc.unload();
        expect(svc.isLoaded, isFalse);

        final r = ProcessInfo.currentRss;
        rss.add(r);
        // ignore: avoid_print
        print(
          'RSS after imagine cycle $i: ${(r / (1024 * 1024)).toStringAsFixed(1)} MB',
        );
      }

      // Per-cycle growth from the first stabilised cycle to the last. The SD
      // 1.5 working set is ~1.6 GB; if free_sd_ctx were skipped, EACH cycle
      // would retain a full context and this single-cycle delta would land at
      // ~1.6 GB+. The ceiling sits well below that so a real free-path
      // regression fails loudly, yet above the mmap/Metal residual noise this
      // measurement carries (the model is mmap'd, so freed file pages linger in
      // RSS until memory pressure — standalone this delta is even negative).
      // ponytail: 1500 MB ceiling < one un-freed ctx; tighten if it regresses.
      final growthMb = (rss.last - rss[1]) / (1024 * 1024);
      // ignore: avoid_print
      print(
        'imagine RSS growth cycles 1->${cycles - 1}: ${growthMb.toStringAsFixed(1)} MB',
      );
      expect(
        growthMb,
        lessThan(1500),
        reason:
            'RSS grew ${growthMb.toStringAsFixed(1)} MB in one reload — '
            'free_sd_ctx is not reclaiming the ~1.6 GB context',
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
    skip: skip,
  );
}
