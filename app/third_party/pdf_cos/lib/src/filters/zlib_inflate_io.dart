import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'decode_budget.dart';

/// Native zlib (archive's `ZLibDecoder` is dart:io's `ZLibCodec` here). It
/// already ignores bytes after the zlib stream and rejects a bad header or a
/// wrong Adler-32 on its own, so [strict] is not consulted.
///
/// dhruva: bounded decode. [stage] caps the output: archive's
/// `maxOutputSize` streams the native codec's output in chunks and throws
/// the moment the cap is crossed, so a bomb never allocates past it. Without
/// a [stage] the call still gets a fresh per-stream cap.
Uint8List inflateZlib(Uint8List data,
    {bool strict = false, DecodeStage? stage}) {
  stage ??= DecodeBudget().stage();
  final Uint8List out;
  try {
    out = const ZLibDecoder().decodeBytes(data, maxOutputSize: stage.remaining);
  } on ArchiveLimitException {
    stage.trip('inflated output past the limit');
  }
  stage.add(out.length);
  return out;
}
