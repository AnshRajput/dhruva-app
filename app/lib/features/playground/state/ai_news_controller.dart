/// AI news: an OPT-IN, on-device digest of small GGUF models worth trying —
/// "This week in on-device AI" (PlaygroundMock.astro; VIDEO_FIXES.md P2 #7).
///
/// Zero telemetry, zero third-party news service. Dhruva's ONLY permitted
/// network call is user-initiated Hugging Face model browsing (CLAUDE.md), so
/// the digest is DERIVED from that same [HfApiClient]: the proven empty-query
/// popular-GGUF search (the exact call `models_hub` makes on build) filtered
/// on-device to repos whose id encodes a sub-2B parameter count
/// (`paramBillionsFromName`). No fetch happens on [build] — it only runs when
/// the user taps to load, which is the opt-in.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../data/hf_api/mobile_suitability.dart';
import '../../../data/hf_api/models/hf_model_summary.dart';

/// `null` = not yet requested (opt-in idle). A non-null list = the loaded
/// digest (possibly empty if nothing sub-2B surfaced).
final aiNewsControllerProvider =
    AsyncNotifierProvider<AiNewsController, List<HfModelSummary>?>(
      AiNewsController.new,
    );

/// Largest param-count (billions) a repo id may encode to count as "small".
const _subBillionsCeiling = 2.0;

/// How many digest items to surface.
const _digestSize = 6;

class AiNewsController extends AsyncNotifier<List<HfModelSummary>?> {
  @override
  Future<List<HfModelSummary>?> build() async => null; // opt-in: no network

  /// Fetches the digest. Called only from a user tap (the opt-in).
  Future<void> load() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetchDigest);
  }

  Future<List<HfModelSummary>> _fetchDigest() async {
    final client = ref.read(hfApiClientProvider);
    final result = await client.searchGgufModels(query: '', limit: 50);
    final seen = <String>{};
    final digest = <HfModelSummary>[];
    for (final m in result.items) {
      final b = paramBillionsFromName(m.id);
      if (b == null || b >= _subBillionsCeiling) continue;
      if (!seen.add(m.id)) continue;
      digest.add(m);
      if (digest.length >= _digestSize) break;
    }
    return digest;
  }
}
