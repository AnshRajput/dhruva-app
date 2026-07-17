/// Pure "which quant do we download when the user just taps Download on a
/// search-result row" rule. No I/O — callers pass the repo's parsed
/// [QuantVariant]s (from `HfApiClient.quantVariantsFrom`).
///
/// The listing (search results) can't show a quant picker — the user hasn't
/// drilled into the repo — so a sensible default is chosen for them here.
/// The model detail screen remains the place to pick a specific quant.
library;

import 'package:path/path.dart' as p;

import 'models/quant_variant.dart';

/// Picks the default download quant from [quants]:
///  1. skip projector files (`mmproj*`) — they're not a standalone chat model;
///  2. prefer an exact `Q4_K_M` (the community default balance of size/quality);
///  3. else the smallest file in the `Q4` family;
///  4. else the smallest file overall ("smallest reasonable").
///
/// Ties are ALWAYS broken by smallest file size — a repo can carry two files
/// sharing one quant label (e.g. a root `Q4_K_M` and a subfolder imatrix
/// duplicate). Returning "whichever came first in file-tree order" was
/// non-deterministic and could hand the user the LARGER file (QA Phase B).
///
/// Returns null if [quants] has no usable (non-projector) entry.
QuantVariant? pickDefaultQuant(List<QuantVariant> quants) {
  final candidates = quants
      .where((q) => !p.basename(q.file.path).toLowerCase().contains('mmproj'))
      .toList();
  if (candidates.isEmpty) return null;

  // Smallest exact-Q4_K_M match wins over any other quant (step 2), but among
  // duplicate Q4_K_M files the smallest is deterministic.
  final exact = candidates.where((q) => q.label == 'Q4_K_M').toList();
  final q4 = candidates.where((q) => q.label.startsWith('Q4')).toList();
  final pool = exact.isNotEmpty ? exact : (q4.isNotEmpty ? q4 : candidates);
  // ponytail: smallest-by-size is the "reasonable" default for a phone; a
  // heavier quant-quality heuristic can replace this if it ever matters.
  pool.sort((a, b) => a.file.sizeBytes.compareTo(b.file.sizeBytes));
  return pool.first;
}
