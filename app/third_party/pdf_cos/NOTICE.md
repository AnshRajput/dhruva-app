# Dhruva modifications to pdf_cos

This directory is `pdf_cos` 14.0.0 from pub.dev (Apache-2.0, see `LICENSE`),
copied unmodified except for the changes below. Every changed line is marked
`// dhruva: bounded decode`, `// dhruva: parse limits` or
`// dhruva: allocation clamps`.

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
(Round 7 removed `pdf_document` and `pdf_graphics` from the app entirely; see
below. The limits still live here because the app's own extractor uses this
package's `ContentStreamParser`.)

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

## Round 7: no font programs, and allocation clamps

Round 6 found single allocations sized from font-program fields (a Type 1
`/Subrs 300000000` became a 1.6 GB `List.filled`) inside `pdf_graphics`, which
no per-stage cap or RSS watchdog can interrupt. The app no longer uses
`pdf_document` or `pdf_graphics`: text extraction is
`lib/data/docs/pdf_text_extractor.dart`, built on this package only, and it
never reads `FontFile*`, `CIDToGIDMap`, ICC profiles, patterns, images or
shadings. This package was grepped for every allocation sized from file
values (`List.filled`, `Uint8List(`, `Float64List(`, `Int32List(`,
`Uint16List(`, `BytesBuilder`, growable lists and maps in count-driven
loops). Each site, and what was done:

Changed (marked `// dhruva: allocation clamps`):

- `xref.dart` `_parseStream` (xref stream rows): `/W` entries must be 0..8
  and the row at least 1 byte (`/W [0 0 0]` with `/Index [0 2000000000]` used
  to add an entry per iteration from no input); the row count is clamped by
  the decoded data and by `cosMaxXrefEntries` (1,000,000).
- `xref.dart` `_parseTable` and `walkFrom`: entries per section and in the
  merged chain capped at `cosMaxXrefEntries`.
- `document.dart` `_scanObjectHeaders` (recovery and rescue scans): scanned
  object map capped at `cosMaxXrefEntries`.
- `document.dart` `_ObjectStream`: `/N` clamped by `data.length ~/ 4 + 1`
  (a header pair is at least 4 bytes) before it drives the index loop.
- `parser.dart`: `CosParser` object nesting capped at 64 (`[[[[...` no longer
  recurses the stack; it throws `CosParseException`).

Audited and already bounded (no change):

- `filters/ccitt.dart` `Uint8List(rows * rowBytes)`: charged to the decode
  stage first (`rows` and `columns` are checked against `stage.remaining`),
  so at most 4 MB.
- `filters/predictor.dart` `Uint8List(rowCount * bytesPerRow)` and `prior`:
  charged first, `bytesPerRow` checked against the stream cap,
  `rowCount = data.length ~/ (bytesPerRow + 1)`.
- `filters/lzw.dart` (four fixed 4096-entry arrays), `filters/mq.dart`
  (constants), `filters/decode_budget.dart` `DecodeBuffer` (doubles up to the
  stage's remaining budget), `run_length.dart`, `ascii.dart`.
- `content_parser.dart` `Float64List`/`Uint8List` operand arrays: grow by
  doubling to at most `maxOperands` (100,000).
- `lexer.dart` string/name `BytesBuilder`s: bounded by the input.
- `byte_source.dart` `Uint8List(len)`: the progressive loader, which the app
  never calls.
- `crypto/*`: reached only for an encrypted file, which the app refuses
  before `CosDocument.open` (`pdfGuard`) and again after it. Sizes there come
  from fixed digest/key lengths or `sublist` calls that throw instead of
  allocating.
- `objects.dart` `CosString.fromText`, `compactor.dart`, `builder.dart`,
  `serializer.dart`, `updater.dart`, `xref_writer.dart`: writer side, never run
  for text extraction.
- `filters/jbig2.dart`, `filters/jpx.dart`: not registered in `decodeStream`'s
  filter table; only image rendering would call them, which the app never does.

Not covered: JBIG2/JPX image decoders (run only when rendering images, which
text extraction never does) and the `tool/`, `test/`, `example/` folders
(not copied).
