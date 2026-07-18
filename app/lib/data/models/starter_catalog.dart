/// The curated mobile-model catalog (PRD v0.3 WS1): a hand-verified set of
/// ~10-12 models that genuinely run on phones, shown as the DEFAULT Models
/// experience instead of the raw Hugging Face firehose. Each entry has a
/// friendly name, a one-line "best for…", a confirmed Q4_K_M download size,
/// and (via [isVision]) whether it carries an mmproj vision projector.
///
/// Lives in `data/` (not a feature) because TWO features consume it —
/// `features/models_hub`'s curated tab AND `features/onboarding`'s
/// "pick your first model" step — and ADR-002 bans a feature importing
/// another feature. `models_hub`'s `recommended_models_provider.dart`
/// re-exports it so its existing importers are untouched.
///
/// Repo ids + Q4_K_M file sizes were verified against the live HF API
/// (`/api/models/{repo}/tree/main`) — see the WS1 blackboard note. A catalog
/// service / remote config stays YAGNI: this list changes on the order of "a
/// research pass", not per-release, so a const list is the right home. The
/// download itself resolves the exact quant file at tap time
/// (`pickDefaultQuant` over the repo's real file tree), so these sizes only
/// drive the size label + device-tier verdict, not the download URL.
library;

import '../../core/device_info/model_tier.dart';

final class StarterModel {
  final String repoId;
  final String displayName;

  /// One-line "best for…" value statement shown on the curated card.
  final String bestFor;

  /// Confirmed Q4_K_M download size in bytes, used for the card's size label
  /// and device-tier classification. For a vision entry ([isVision]) this is
  /// the COMBINED footprint (model + its mmproj projector), since both load
  /// into memory together — the same accounting `classifyModelTier`'s
  /// `mmprojSizeBytes` does — so the verdict is honest about the real cost.
  final int approxSizeBytes;

  /// True for a vision-capable model whose repo ships an mmproj projector.
  /// The one-tap download resolves and chains that projector automatically
  /// (`ListingDownloadController.download`), so the card needs no extra
  /// affordance — only a "Vision" label.
  final bool isVision;

  const StarterModel({
    required this.repoId,
    required this.displayName,
    required this.bestFor,
    required this.approxSizeBytes,
    this.isVision = false,
  });
}

/// Ordered smallest → largest so the default view leads with the most
/// broadly-runnable picks; the curated tab re-sorts by device-fit on top of
/// this when the RAM reading is known.
const starterModelCatalog = <StarterModel>[
  StarterModel(
    repoId: 'bartowski/Qwen2.5-0.5B-Instruct-GGUF',
    displayName: 'Qwen2.5 0.5B Instruct',
    bestFor: 'Best for instant replies on any phone',
    approxSizeBytes: 397808192, // ~379 MB
  ),
  StarterModel(
    repoId: 'TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF',
    displayName: 'TinyLlama 1.1B Chat',
    bestFor: 'Best for a tiny, classic all-round chat',
    approxSizeBytes: 668788096, // ~638 MB
  ),
  StarterModel(
    repoId: 'bartowski/Llama-3.2-1B-Instruct-GGUF',
    displayName: 'Llama 3.2 1B Instruct',
    bestFor: 'Best for everyday chat on modest phones',
    approxSizeBytes: 807694464, // ~770 MB
  ),
  StarterModel(
    repoId: 'bartowski/Qwen2.5-1.5B-Instruct-GGUF',
    displayName: 'Qwen2.5 1.5B Instruct',
    bestFor: 'Best for a balance of speed and quality',
    approxSizeBytes: 986048768, // ~940 MB
  ),
  StarterModel(
    repoId: 'bartowski/SmolLM2-1.7B-Instruct-GGUF',
    displayName: 'SmolLM2 1.7B Instruct',
    bestFor: 'Best for fast, on-device assistance',
    approxSizeBytes: 1055609824, // ~1.0 GB
  ),
  StarterModel(
    repoId: 'bartowski/gemma-2-2b-it-GGUF',
    displayName: 'Gemma 2 2B Instruct',
    bestFor: 'Best for richer, more polished answers',
    approxSizeBytes: 1708582752, // ~1.6 GB
  ),
  StarterModel(
    repoId: 'ggml-org/SmolVLM2-2.2B-Instruct-GGUF',
    displayName: 'SmolVLM2 2.2B (Vision)',
    bestFor: 'Best for describing photos and images',
    approxSizeBytes: 1984906336, // ~1.85 GB (model + mmproj projector)
    isVision: true,
  ),
  StarterModel(
    repoId: 'bartowski/Qwen2.5-3B-Instruct-GGUF',
    displayName: 'Qwen2.5 3B Instruct',
    bestFor: 'Best for stronger reasoning and coding',
    approxSizeBytes: 1929903264, // ~1.8 GB
  ),
  StarterModel(
    repoId: 'bartowski/Llama-3.2-3B-Instruct-GGUF',
    displayName: 'Llama 3.2 3B Instruct',
    bestFor: 'Best for the most capable everyday chat',
    approxSizeBytes: 2019377696, // ~1.9 GB
  ),
  StarterModel(
    repoId: 'bartowski/Phi-3.5-mini-instruct-GGUF',
    displayName: 'Phi-3.5 mini Instruct',
    bestFor: 'Best for reasoning and step-by-step tasks',
    approxSizeBytes: 2393232672, // ~2.2 GB
  ),
  StarterModel(
    repoId: 'unsloth/Phi-4-mini-instruct-GGUF',
    displayName: 'Phi-4 mini Instruct',
    bestFor: 'Best for math and structured reasoning',
    approxSizeBytes: 2491874272, // ~2.3 GB
  ),
];

/// The curated catalog's friendly name for [repoId], or the raw repo id when
/// the model was imported / found via advanced HF search (not curated). Used
/// everywhere a download surfaces a model to the user — the Downloads screen,
/// the completion SnackBar, the Installed tabs — so a curated model never
/// reverts to its cryptic HF path (PRD v0.3 WS1/WS4 "no jargon").
String friendlyModelName(String repoId) =>
    _friendlyNamesByRepo[repoId] ?? repoId;

final _friendlyNamesByRepo = {
  for (final m in starterModelCatalog) m.repoId: m.displayName,
};

/// The single model onboarding pre-selects and badges "Recommended" (PRD v0.3
/// WS2): the MOST capable text model that still runs *comfortably* on this
/// device, so a first-timer gets the best experience their phone can hold
/// without touching a quant menu.
///
/// Rules, in order:
/// 1. Largest catalog entry classified [ModelTier.comfortable] on the device.
/// 2. Else the largest entry that's at least [ModelTier.possible].
/// 3. Else (RAM unknown, or nothing fits) the smallest entry — always
///    runnable, never a dead-end.
///
/// Vision models are excluded: the first-run pick is a chat model (vision is
/// a specialty the catalog surfaces separately). The catalog is ordered
/// smallest → largest, so the LAST match in a pass is the largest.
StarterModel recommendedStarterModel(int? totalRamBytes) {
  final textModels = starterModelCatalog.where((m) => !m.isVision).toList();
  if (totalRamBytes == null) return textModels.first;

  StarterModel? bestComfortable;
  StarterModel? bestPossible;
  for (final m in textModels) {
    final tier = classifyModelTier(
      fileSizeBytes: m.approxSizeBytes,
      totalRamBytes: totalRamBytes,
    );
    switch (tier) {
      case ModelTier.comfortable:
        bestComfortable = m;
      case ModelTier.possible:
        bestPossible = m;
      case ModelTier.notRecommended:
        break;
    }
  }
  return bestComfortable ?? bestPossible ?? textModels.first;
}
