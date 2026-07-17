/// Pure filename → GGUF quant label extraction. No I/O.
library;

/// Matches llama.cpp's quant naming convention: `Q<n>_<K|0|1>[_S|M|L]`,
/// `IQ<n>_<XXS|XS|S|M|NL>`, or a raw-precision tag (`F16`, `F32`, `BF16`).
/// Case-insensitive in the source filename; the returned label is always
/// upper-cased to match llama.cpp's own convention (e.g. "Q4_K_M").
final _quantPattern = RegExp(
  r'(IQ[1-4]_(?:XXS|XS|S|M|NL)|Q[2-8]_(?:K_[SML]|K|[01])|F16|F32|BF16)',
  caseSensitive: false,
);

/// Extracts the quant token from a GGUF filename, e.g.
/// `"Qwen2.5-1.5B-Instruct-Q4_K_M.gguf"` -> `"Q4_K_M"`. Returns null if no
/// known quant token is found (e.g. a projector file like
/// `"mmproj-Q8_0.gguf"` still matches "Q8_0"; a file with no quant marker at
/// all, like a tokenizer or README, returns null).
String? extractQuantVariant(String fileName) {
  final match = _quantPattern.firstMatch(fileName);
  return match?.group(0)?.toUpperCase();
}
