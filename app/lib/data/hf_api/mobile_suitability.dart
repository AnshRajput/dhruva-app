/// Pure, name-only "is this model phone-suitable" heuristic for ranking raw
/// Hugging Face search results. The search endpoint carries no file size or
/// parameter count (only `getRepoFiles` does, one HTTP call per repo — too
/// expensive to do per scroll row), so this reads the parameter-count token
/// most GGUF repo ids already encode (e.g. `.../Llama-3.2-3B-Instruct-GGUF`
/// → 3B) and buckets by it. No I/O.
library;

/// Ranking bucket for a search row — lower sorts first.
enum MobileSuitability {
  /// Known small (≤ [_friendlyMaxB] B params): great on a phone — floats up.
  friendly,

  /// Unknown size, or a mid-size model (a few-to-~13B): left in HF's own
  /// popularity order.
  neutral,

  /// Known large (> [_heavyMaxB] B params, e.g. 70B/34B/13B): unlikely to
  /// run on a phone — sinks to the bottom.
  heavy,
}

const _friendlyMaxB = 4.0;
const _heavyMaxB = 13.0;

/// Matches a parameter-count token like `70B`, `13B`, `7B`, `3B`, `1.5B`,
/// `0.5B`, or an `8x7B` MoE (the leading count times the expert size). Word
/// boundaries keep it from matching `1B` inside a hash or `Q4` inside a quant.
final _paramPattern = RegExp(
  r'(?<![A-Za-z0-9.])(\d+(?:\.\d+)?)\s*[xX]\s*(\d+(?:\.\d+)?)\s*[bB]\b'
  r'|(?<![A-Za-z0-9.])(\d+(?:\.\d+)?)\s*[bB]\b',
);

/// Largest parameter count (in billions) named anywhere in [repoId], or null
/// if the id encodes no recognizable size token.
double? paramBillionsFromName(String repoId) {
  double? max;
  for (final m in _paramPattern.allMatches(repoId)) {
    final double value;
    if (m.group(1) != null && m.group(2) != null) {
      // "8x7B" MoE — count the total activated-expert params (8 * 7).
      value = double.parse(m.group(1)!) * double.parse(m.group(2)!);
    } else {
      value = double.parse(m.group(3)!);
    }
    if (max == null || value > max) max = value;
  }
  return max;
}

/// Buckets [repoId] for mobile-suitability ranking. Unknown size is
/// [MobileSuitability.neutral] on purpose: most small community repos don't
/// encode a size token, so demoting the unknowns would bury good picks.
MobileSuitability mobileSuitabilityOf(String repoId) {
  final b = paramBillionsFromName(repoId);
  if (b == null) return MobileSuitability.neutral;
  if (b <= _friendlyMaxB) return MobileSuitability.friendly;
  if (b > _heavyMaxB) return MobileSuitability.heavy;
  return MobileSuitability.neutral;
}

/// Stable re-rank: known-small models float up, known-large sink, everything
/// else keeps Hugging Face's popularity order. Sorting each page in isolation
/// is intentional — a heuristic, not a global re-sort.
List<T> rankByMobileSuitability<T>(List<T> items, String Function(T) repoIdOf) {
  final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
  indexed.sort((a, b) {
    final ra = mobileSuitabilityOf(repoIdOf(a.$2)).index;
    final rb = mobileSuitabilityOf(repoIdOf(b.$2)).index;
    if (ra != rb) return ra.compareTo(rb);
    return a.$1.compareTo(b.$1); // stable
  });
  return [for (final e in indexed) e.$2];
}
