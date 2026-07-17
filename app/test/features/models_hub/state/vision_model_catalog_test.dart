import 'package:dhruva/features/models_hub/state/vision_model_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'catalog has the two Loop-7-verified entries, each with a projector',
    () {
      expect(visionModelCatalog, hasLength(2));
      for (final model in visionModelCatalog) {
        expect(model.mmprojFileName, isNotEmpty);
        expect(model.mmprojSizeBytes, greaterThan(0));
        expect(
          model.combinedSizeBytes,
          model.modelSizeBytes + model.mmprojSizeBytes,
        );
      }
    },
  );

  test('visionCatalogQuantVariant produces a vision-paired QuantVariant, the '
      'same shape a live HF repo listing would', () {
    final variant = visionCatalogQuantVariant(visionModelCatalog.first);
    expect(variant.isVision, isTrue);
    expect(variant.label, visionModelCatalog.first.quant);
    expect(variant.file.path, visionModelCatalog.first.modelFileName);
    expect(variant.mmprojFile!.path, visionModelCatalog.first.mmprojFileName);
  });
}
