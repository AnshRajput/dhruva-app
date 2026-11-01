/// Per-variant quality/effectiveness guidance for a GGUF quant, plus the plain
/// words used wherever a quant label would otherwise show up raw (D6: "Q4_K_M"
/// is jargon on a primary path; it lives only behind an "Advanced" expander).
///
/// IMPORTANT: this is a HEURISTIC from the quant's name (e.g. `Q4_K_M`,
/// `IQ3_M`, `Q8_0`, `F16`), NOT a measured benchmark — smaller quants trade
/// accuracy for size, larger ones approach the full-precision model. Mirrors
/// the same quant-family reasoning `pickDefaultQuant` uses to default to
/// `Q4_K_M`.
library;

/// The four quality bands a GGUF quant name maps to.
enum QuantQuality {
  lower(
    'Smaller · lower quality',
    'Smaller',
    'Fits tight storage, but noticeably less accurate.',
  ),
  balanced(
    'Balanced · recommended',
    'Balanced',
    'The community default — good quality for its size.',
  ),
  higher(
    'Higher quality · larger',
    'Sharper',
    'Closer to the original; needs more space and RAM.',
  ),
  nearLossless(
    'Near-lossless · largest',
    'Sharpest',
    'Barely distinguishable from full precision; biggest files.',
  );

  const QuantQuality(this.label, this.plainName, this.blurb);

  /// Short pill copy, e.g. "Balanced · recommended".
  final String label;

  /// One plain word for primary paths: Smaller / Balanced / Sharper /
  /// Sharpest.
  final String plainName;

  /// One-line "what this means" shown under the chip.
  final String blurb;
}

/// Classify a quant [label] into a [QuantQuality] band by parsing its bit
/// level. Float families (`F16`/`F32`/`BF16`) are effectively lossless; Q/IQ
/// families split on the bit count (≤3 lower · 4 balanced · 5-6 higher · 8+
/// near-lossless). Unrecognized labels fall back to [QuantQuality.balanced]
/// (a neutral guess rather than a scary one).
QuantQuality classifyQuantQuality(String label) {
  final l = label.toUpperCase();
  if (l.startsWith('F16') || l.startsWith('F32') || l.startsWith('BF16')) {
    return QuantQuality.nearLossless;
  }
  // First digit run after an optional `I` and the `Q` prefix is the bit level.
  final match = RegExp(r'I?Q(\d+)').firstMatch(l);
  if (match == null) return QuantQuality.balanced;
  final bits = int.parse(match.group(1)!);
  if (bits <= 3) return QuantQuality.lower;
  if (bits == 4) return QuantQuality.balanced;
  if (bits <= 6) return QuantQuality.higher;
  return QuantQuality.nearLossless;
}

/// Plain label for an installed/downloadable file's quant: "Balanced",
/// "Smaller", "Sharper", "Sharpest". Null/blank (an imported file of unknown
/// quant) reads "Custom file" rather than "unknown quant".
String plainQuantName(String? quant) {
  final q = quant?.trim();
  if (q == null || q.isEmpty) return 'Custom file';
  return classifyQuantQuality(q).plainName;
}

/// The model's human name: the repo's last path segment without the "-GGUF"
/// suffix ("bartowski/Llama-3.2-1B-Instruct-GGUF" -> "Llama-3.2-1B-Instruct").
String humanModelName(String repoId) {
  final segment = repoId.split('/').last;
  return segment.toUpperCase().endsWith('-GGUF')
      ? segment.substring(0, segment.length - 5)
      : segment;
}
