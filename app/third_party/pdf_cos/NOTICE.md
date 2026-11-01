# Dhruva modifications to pdf_cos

This directory is `pdf_cos` 14.0.0 from pub.dev (Apache-2.0, see `LICENSE`),
copied unmodified except for the changes below. Every changed line is marked
`// dhruva: bounded decode`.

## What changed and why

Upstream decodes every stream filter with no output cap, so a ~100 KB PDF
(a Flate stream of zeros, an ASCII85 `z` run, a RunLength run, an LZW chain, a
huge predictor row) expands to hundreds of MB and kills the app. A guard
outside the parser kept being bypassed because it had to guess where the
parser thinks a stream ends. The cap now lives inside the decoders.

- `lib/src/filters/decode_budget.dart` (new): `DecodeBudget` (16 MB per
  filter stage, 128 MB per document by default) and `DecodeStage`.
- `lib/src/exceptions.dart`: new `PdfDecodeLimitExceeded`.
- `filters/*.dart`: `CosFilter.decode` takes a `DecodeBudget`; FlateDecode
  (VM: archive `maxOutputSize`, a chunked native inflate that throws as soon
  as the cap is crossed; web: output buffer never grows past the cap),
  ASCIIHex, ASCII85, LZW, RunLength, CCITT and the PNG/TIFF predictor charge
  their output before allocating it. Predictor parameters are validated so a
  hostile /Columns cannot size a buffer or loop forever.
- `document.dart`: `CosDocument.decodeBudget`, shared by every stream decoded
  for the document. `xref.dart`: one budget per xref reader.
- `pubspec.yaml`: workspace resolution and dev dependencies removed, `archive`
  raised to ^4.6.0 (needed for `maxOutputSize`).

Not covered: JBIG2/JPX image decoders (run only when rendering images, which
text extraction never does) and the `tool/`, `test/`, `example/` folders
(not copied).
