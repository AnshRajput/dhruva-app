/// Pure, unit-testable download decision logic — deliberately separated
/// from `download_backend.dart` (the thin `background_downloader` plugin
/// adapter, which needs platform channels and so can't run under
/// `flutter test`). Same split as `engine_bindings`: native/plugin glue
/// stays thin, the logic that decides right-vs-wrong stays pure and gets
/// exhaustive tests.
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../core/failures/app_failure.dart';

/// Sanitizes a caller-supplied local file name for writing under
/// `modelsDirectory`. `DownloadManager.enqueue` is the trust boundary for
/// every path that ends up on disk, so it can't assume a caller already
/// stripped directory components — a raw HF tree path legitimately looks
/// like `"mmproj/model-Q8_0.gguf"` (subfolder files), and a hostile
/// `fileName` can look like `"../../../etc/x.gguf"`. Both get flattened to
/// their basename; only the basename is used for the on-disk name (the
/// remote resolve URL is a separate field and is never touched here).
/// Returns null — reject — when the basename is empty, a bare `.`/`..`, or
/// (the `"///"` edge case: `p.basename` of an all-separator string returns
/// the separator itself, e.g. `"/"`, which `p.join` then treats as an
/// absolute-path override and escapes `modelsDirectory` entirely) still
/// contains a separator — i.e. not a name that can identify a real file.
String? sanitizeLocalFileName(String fileName) {
  final base = p.basename(fileName);
  if (base.isEmpty || base == '.' || base == '..') return null;
  if (base.contains('/') || base.contains(r'\')) return null;
  return base;
}

/// The 4-byte magic every valid GGUF file starts with (ASCII "GGUF").
const ggufMagicBytes = [0x47, 0x47, 0x55, 0x46];

/// Checks [header] (the first bytes of a file — 4 or more) for the GGUF
/// magic. Returns false (not a crash) for short/wrong input so callers can
/// turn it into a typed [StorageCorruptFileFailure].
bool hasGgufMagic(List<int> header) {
  if (header.length < ggufMagicBytes.length) return false;
  for (var i = 0; i < ggufMagicBytes.length; i++) {
    if (header[i] != ggufMagicBytes[i]) return false;
  }
  return true;
}

/// Verifies a completed download/import. Size is always checked (HF always
/// reports it, in the search/tree response or the `x-linked-size` header).
/// Checksum is checked only when both sides know one — the tree endpoint's
/// `lfs.oid` sha256 isn't present for every file (small, non-LFS files
/// don't have one — see orchestra/research/hf-api.md §2).
StorageCorruptFileFailure? verifyIntegrity({
  required int expectedSizeBytes,
  required int actualSizeBytes,
  String? expectedSha256,
  String? actualSha256,
}) {
  if (actualSizeBytes != expectedSizeBytes) {
    return StorageCorruptFileFailure(
      'size mismatch: expected $expectedSizeBytes bytes, got $actualSizeBytes',
    );
  }
  if (expectedSha256 != null &&
      actualSha256 != null &&
      expectedSha256.toLowerCase() != actualSha256.toLowerCase()) {
    return const StorageCorruptFileFailure('checksum mismatch');
  }
  return null;
}

/// sha256 of a full file's bytes, hex-encoded lowercase — matches the
/// format of the HF tree endpoint's `lfs.oid`.
String sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();

/// Guards a write of [requiredBytes] against [freeBytes] free space, kept
/// with [marginBytes] headroom afterwards (default 200MB) so the device
/// never gets driven to exactly zero free space.
StorageInsufficientSpaceFailure? checkStorageGuard({
  required int requiredBytes,
  required int freeBytes,
  int marginBytes = 200 * 1024 * 1024,
}) {
  final needed = requiredBytes + marginBytes;
  if (freeBytes < needed) {
    return StorageInsufficientSpaceFailure(
      'not enough free space: need ${_formatBytes(needed)}, '
      'have ${_formatBytes(freeBytes)} free',
      requiredBytes: needed,
      availableBytes: freeBytes,
    );
  }
  return null;
}

String _formatBytes(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
