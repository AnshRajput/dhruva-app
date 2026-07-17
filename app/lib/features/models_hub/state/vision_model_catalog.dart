/// Curated vision-model catalog (Loop-7 T2 §6) — same shape/purpose as
/// `recommended_models_provider.dart`'s `starterModelCatalog`, but for the
/// two vision models this loop verified real repos/sizes for (orchestra/
/// BLACKBOARD.md LOOP-07 PLAN, orchestra/research/hf-api.md §5): a small
/// SmolVLM-500M pair for low-end devices, and the SmolVLM2-2.2B pair
/// native-engine proved a real round-trip against (T1 HANDOFF). A remote
/// catalog service is YAGNI for two hand-picked entries, same reasoning as
/// the starter catalog.
library;

import '../../../data/hf_api/models/hf_repo_file.dart';
import '../../../data/hf_api/models/quant_variant.dart';

final class VisionCatalogModel {
  final String repoId;
  final String displayName;
  final String modelFileName;
  final int modelSizeBytes;
  final String quant;
  final String mmprojFileName;
  final int mmprojSizeBytes;

  const VisionCatalogModel({
    required this.repoId,
    required this.displayName,
    required this.modelFileName,
    required this.modelSizeBytes,
    required this.quant,
    required this.mmprojFileName,
    required this.mmprojSizeBytes,
  });

  int get combinedSizeBytes => modelSizeBytes + mmprojSizeBytes;
}

const visionModelCatalog = <VisionCatalogModel>[
  VisionCatalogModel(
    repoId: 'ggml-org/SmolVLM-500M-Instruct-GGUF',
    displayName: 'SmolVLM 500M Instruct',
    modelFileName: 'SmolVLM-500M-Instruct-Q8_0.gguf',
    modelSizeBytes: 436207616, // ~416 MB — orchestra/BLACKBOARD.md LOOP-07
    quant: 'Q8_0',
    mmprojFileName: 'mmproj-SmolVLM-500M-Instruct-Q8_0.gguf',
    mmprojSizeBytes: 108003328, // ~103 MB
  ),
  VisionCatalogModel(
    repoId: 'ggml-org/SmolVLM2-2.2B-Instruct-GGUF',
    displayName: 'SmolVLM2 2.2B Instruct',
    modelFileName: 'SmolVLM2-2.2B-Instruct-Q4_K_M.gguf',
    modelSizeBytes: 1112473600, // ~1061 MB
    quant: 'Q4_K_M',
    mmprojFileName: 'mmproj-SmolVLM2-2.2B-Instruct-Q8_0.gguf',
    mmprojSizeBytes: 592445440, // ~565 MB
  ),
];

/// Builds the [QuantVariant] `download_actions_controller.dart`'s
/// `enqueueVisionQuant` expects, from a catalog entry — the same pairing
/// shape a live HF repo listing would produce (see `HfApiClient.
/// quantVariantsFrom`), so the catalog rides the exact same download path as
/// a Model Manager search result rather than a second one.
QuantVariant visionCatalogQuantVariant(VisionCatalogModel model) =>
    QuantVariant(
      label: model.quant,
      file: HfRepoFile(
        path: model.modelFileName,
        sizeBytes: model.modelSizeBytes,
      ),
      mmprojFile: HfRepoFile(
        path: model.mmprojFileName,
        sizeBytes: model.mmprojSizeBytes,
      ),
    );
