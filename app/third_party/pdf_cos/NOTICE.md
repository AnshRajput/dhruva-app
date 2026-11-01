# Dhruva modifications to pdf_cos

This directory is `pdf_cos` 14.0.0 from pub.dev (Apache-2.0, see `LICENSE`),
copied unmodified except for the changes below. Every changed line is marked
`// dhruva: bounded decode` or `// dhruva: parse limits`.

## What changed and why

Upstream decodes every stream filter with no output cap, so a ~100 KB PDF
(a Flate stream of zeros, an ASCII85 `z` run, a RunLength run, an LZW chain, a
huge predictor row) expands to hundreds of MB and kills the app. A guard
outside the parser kept being bypassed because it had to guess where the
parser thinks a stream ends. The cap now lives inside the decoders.

- `lib/src/filters/decode_budget.dart` (new): `DecodeBudget` (4 MB per
  filter stage, 64 MB per document by default; see round 6) and `DecodeStage`.
- `lib/src/exceptions.dart`: new `PdfDecodeLimitExceeded`.
- `filters/*.dart`: `CosFilter.decode` takes a `DecodeBudget`; FlateDecode
  (VM: archive `maxOutputSize`, a chunked native inflate that throws as soon
  as the cap is crossed; web: output buffer never grows past the cap),
  ASCIIHex, ASCII85, LZW, RunLength, CCITT and the PNG/TIFF predictor charge
  their output before allocating it. Predictor parameters are validated so a
  hostile /Columns cannot size a buffer or loop forever.
- `document.dart`: `CosDocument.decodeBudget`, shared by every stream decoded
  for the document. `xref.dart`: one budget per xref reader.
- Memory, not just bytes (round 5). A capped output made of 1-2 byte runs or
  codes still cost 30-40x its size in per-run objects (a 16 MB RunLength
  stream measured ~1.2 GB of real memory; LZW similar). So:
  - `filters/decode_budget.dart`: `DecodeBuffer`, ONE `Uint8List` that
    doubles up to the stage's remaining budget (`addByte`, `addRange`,
    `fill`, `reserve`, `takeBytes`), and `DecodeBufferStats`, a test hook
    that counts backing-array allocations and peak live bytes.
  - `run_length.dart`: writes through `DecodeBuffer` (was `BytesBuilder(copy:
    false)` plus a new `Uint8List` per run).
  - `lzw.dart`: the dictionary is four fixed 4096-entry arrays (prefix code,
    last byte, first byte, length); a code is expanded by walking the prefix
    chain backwards into the output buffer. No list per literal or per code
    (was a `Uint8List` per code and per table entry). Output through
    `DecodeBuffer`.
  - `ascii.dart`: ASCIIHex and ASCII85 write through `DecodeBuffer`; ASCII85
    no longer allocates a list and a sublist per 4-byte group.
  - `ccitt.dart`: with `/Rows` the result is one preallocated array written
    in place (no `BytesBuilder`, no second padded copy); without it one
    `DecodeBuffer`. One scratch row is reused instead of an array per row.
    A row may hold at most `columns + 4` transitions, so zero-length runs
    cannot grow the list without bound.
  - Flate (archive's own doubling buffer, <= 2x) and the PNG/TIFF predictors
    (one output array, TIFF in place) were audited and left as they are.
  - Audited, not changed: JBIG2/JPX (render-time only, see below) and
    `compactor.dart` (writer side, never run for text extraction).
- One budget per document. `CosXrefReader` takes an optional `decodeBudget`;
  `CosDocument.open`/`_open` creates one budget per open and hands it to the
  xref reader, the recovery path and the resulting `CosDocument`
  (`decodeBudget` is now a constructor field). `applyIncrementalUpdate` reads
  with the document's own budget. In `byte_source.dart` the progressive
  loader owns one budget used by `_parseXrefStream`, `_loadObjStm` and its
  `CosXrefReader`, and opens the document with that same budget
  (`CosDocument.open(decodeBudget:)`). No decode site starts a fresh budget
  except `openAppended` (a new revision, deliberately fresh) and the
  `decodeStream` fallback for callers that pass none.
- Encrypted files are refused by the app (`pdf_inflate_guard.dart`,
  `document_extractor.dart`), not by this package: an encrypted file's
  streams are ciphertext to the guard, and `PdfDocument.open` authenticates
  the empty password. No change to `crypto/`.
- `pubspec.yaml`: workspace resolution and dev dependencies removed, `archive`
  raised to ^4.6.0 (needed for `maxOutputSize`).

## Round 6: parse limits and lower caps

A decoded content stream within the byte cap can still become millions of
objects, each far bigger than the byte behind it (a 24 KB Flate file whose
stream decodes to `BT /F1 12 Tf [(a)-1 (a)-1 ...] TJ ET` drove a read to
2.3 GB; `()`, `<>` and `0 1 Td (a) Tj` repeated cost 580-610 MB).
`pdf_graphics`/`pdf_document` are NOT vendored: the content-stream parser they
call is `ContentStreamParser` in this package, so the limits live here.

- `content_parser.dart` (marked `// dhruva: parse limits`):
  `ContentStreamParser.maxOperations` (500,000 operators per stream, i.e. per
  page or form XObject), `maxOperands` (100,000 operands per operator, array
  or dictionary), `maxNesting` (64). A breach throws `PdfDecodeLimitExceeded`
  and bumps `ContentStreamParser.limitTrips`, which the app compares before
  and after a read because library code swallows per-page exceptions.
- `decode_budget.dart`: defaults lowered to 4 MB per filter stage and 64 MB
  per document (were 16 MB / 128 MB). The stage cap applies to every stream,
  including page content, fonts and ToUnicode CMaps. Real-world need for more:
  none found. Ordinary page content streams are tens to hundreds of KB, a
  ToUnicode CMap well under 1 MB, and a subsetted embedded font under 1 MB
  decoded. A PDF that embeds a full CJK font (10 MB+ decoded) is now refused as
  unsafe; raise `maxStreamBytes` only if that proves common, and only together
  with a check that the app-level memory watchdog still holds.
- The hard guarantee is not in this package: `extractDocumentFile` kills the
  extraction isolate when process RSS grows 350 MB past its starting size.

Not covered: JBIG2/JPX image decoders (run only when rendering images, which
text extraction never does) and the `tool/`, `test/`, `example/` folders
(not copied).
