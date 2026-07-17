import 'package:dhruva/core/device_info/model_tier.dart';
import 'package:flutter_test/flutter_test.dart';

const _gib = 1024 * 1024 * 1024;

void main() {
  group('classifyModelTier — 1B class (<=1.2GiB file)', () {
    const fileSize = 900 * 1024 * 1024; // ~900MB, e.g. Llama-3.2-1B Q4_K_M
    const floor = 4 * _gib;

    test('below floor is notRecommended', () {
      expect(
        classifyModelTier(fileSizeBytes: fileSize, totalRamBytes: floor - 1),
        ModelTier.notRecommended,
      );
    });

    test('exactly at floor is possible', () {
      expect(
        classifyModelTier(fileSizeBytes: fileSize, totalRamBytes: floor),
        ModelTier.possible,
      );
    });

    test('just below comfortable multiplier is possible', () {
      expect(
        classifyModelTier(
          fileSizeBytes: fileSize,
          totalRamBytes: (floor * 1.5).round() - 1,
        ),
        ModelTier.possible,
      );
    });

    test('exactly at comfortable multiplier is comfortable', () {
      expect(
        classifyModelTier(
          fileSizeBytes: fileSize,
          totalRamBytes: (floor * 1.5).round(),
        ),
        ModelTier.comfortable,
      );
    });

    test('well above floor is comfortable', () {
      expect(
        classifyModelTier(fileSizeBytes: fileSize, totalRamBytes: 8 * _gib),
        ModelTier.comfortable,
      );
    });
  });

  group('classifyModelTier — 3-4B class (1.2GiB < file <= 3GiB)', () {
    const fileSize = 2 * _gib; // e.g. Llama-3.2-3B Q4_K_M ~1.9GB
    const floor = 6 * _gib;

    test('below floor is notRecommended', () {
      expect(
        classifyModelTier(fileSizeBytes: fileSize, totalRamBytes: floor - 1),
        ModelTier.notRecommended,
      );
    });

    test('at floor is possible', () {
      expect(
        classifyModelTier(fileSizeBytes: fileSize, totalRamBytes: floor),
        ModelTier.possible,
      );
    });

    test('at comfortable multiplier is comfortable', () {
      expect(
        classifyModelTier(
          fileSizeBytes: fileSize,
          totalRamBytes: (floor * 1.5).round(),
        ),
        ModelTier.comfortable,
      );
    });
  });

  group('classifyModelTier — 4B+ class (file > 3GiB)', () {
    const fileSize =
        4 * _gib; // e.g. unsloth/Phi-4-mini-ish scale, extrapolated
    const floor = 8 * _gib;

    test('below floor is notRecommended', () {
      expect(
        classifyModelTier(fileSizeBytes: fileSize, totalRamBytes: floor - 1),
        ModelTier.notRecommended,
      );
    });

    test('at floor is possible', () {
      expect(
        classifyModelTier(fileSizeBytes: fileSize, totalRamBytes: floor),
        ModelTier.possible,
      );
    });

    test('above comfortable multiplier is comfortable', () {
      expect(
        classifyModelTier(fileSizeBytes: fileSize, totalRamBytes: 16 * _gib),
        ModelTier.comfortable,
      );
    });
  });

  group('classifyModelTier — size-class boundaries', () {
    test('exactly 1.2GiB file still uses the 1B floor (4GiB)', () {
      const boundary = 1258291200; // 1.2 GiB
      expect(
        classifyModelTier(fileSizeBytes: boundary, totalRamBytes: 4 * _gib),
        ModelTier.possible,
      );
    });

    test('1 byte over the 1B boundary uses the 3-4B floor (6GiB)', () {
      const justOver = 1258291201;
      // 4GiB RAM is now below the 6GiB floor for this size class.
      expect(
        classifyModelTier(fileSizeBytes: justOver, totalRamBytes: 4 * _gib),
        ModelTier.notRecommended,
      );
      expect(
        classifyModelTier(fileSizeBytes: justOver, totalRamBytes: 6 * _gib),
        ModelTier.possible,
      );
    });

    test('exactly 3GiB file still uses the 3-4B floor (6GiB)', () {
      const boundary = 3 * _gib;
      expect(
        classifyModelTier(fileSizeBytes: boundary, totalRamBytes: 6 * _gib),
        ModelTier.possible,
      );
    });

    test('1 byte over the 3GiB boundary uses the 4B+ floor (8GiB)', () {
      const justOver = 3 * _gib + 1;
      expect(
        classifyModelTier(fileSizeBytes: justOver, totalRamBytes: 6 * _gib),
        ModelTier.notRecommended,
      );
      expect(
        classifyModelTier(fileSizeBytes: justOver, totalRamBytes: 8 * _gib),
        ModelTier.possible,
      );
    });
  });

  test('quant is accepted but does not change the verdict', () {
    const fileSize = 900 * 1024 * 1024;
    const ram = 4 * _gib;
    final withQuant = classifyModelTier(
      fileSizeBytes: fileSize,
      totalRamBytes: ram,
      quant: 'Q4_K_M',
    );
    final withoutQuant = classifyModelTier(
      fileSizeBytes: fileSize,
      totalRamBytes: ram,
    );
    expect(withQuant, withoutQuant);
  });

  test('zero-byte file classifies as 1B-class and floor still applies', () {
    expect(
      classifyModelTier(fileSizeBytes: 0, totalRamBytes: 4 * _gib),
      ModelTier.possible,
    );
    expect(
      classifyModelTier(fileSizeBytes: 0, totalRamBytes: 4 * _gib - 1),
      ModelTier.notRecommended,
    );
  });

  group('classifyModelTier — vision combined footprint (Loop-7 T2 D4)', () {
    test('mmprojSizeBytes defaults to 0 — unchanged behavior for a plain '
        'text model', () {
      const fileSize = 900 * 1024 * 1024;
      expect(
        classifyModelTier(fileSizeBytes: fileSize, totalRamBytes: 4 * _gib),
        classifyModelTier(
          fileSizeBytes: fileSize,
          totalRamBytes: 4 * _gib,
          mmprojSizeBytes: 0,
        ),
      );
    });

    test(
      'a 416MB model + 103MB projector (~519MB combined) is still 1B-class '
      '(<=1.2GiB), floor 4GB — matches classifying the combined size alone',
      () {
        const modelBytes = 436207616; // ~416 MB
        const mmprojBytes = 108003328; // ~103 MB
        expect(
          classifyModelTier(
            fileSizeBytes: modelBytes,
            totalRamBytes: 4 * _gib,
            mmprojSizeBytes: mmprojBytes,
          ),
          classifyModelTier(
            fileSizeBytes: modelBytes + mmprojBytes,
            totalRamBytes: 4 * _gib,
          ),
        );
      },
    );

    test('the projector pushes a model across a size-class boundary into a '
        'higher RAM floor', () {
      // Model alone (~1.1GiB) is 1B-class (floor 4GB) — "possible" at
      // 4GB RAM (below the 6GB comfortable threshold). Combined with a
      // 200MB projector it crosses the 1.2GiB boundary into the 3-4B
      // floor (6GB), which the same 4GB RAM now fails outright.
      const modelBytes = 1181116006; // ~1.1 GiB
      const mmprojBytes = 200 * 1024 * 1024;
      expect(
        classifyModelTier(fileSizeBytes: modelBytes, totalRamBytes: 4 * _gib),
        ModelTier.possible,
      );
      expect(
        classifyModelTier(
          fileSizeBytes: modelBytes,
          totalRamBytes: 4 * _gib,
          mmprojSizeBytes: mmprojBytes,
        ),
        ModelTier.notRecommended,
      );
    });
  });
}
