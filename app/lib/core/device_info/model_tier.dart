/// Pure "will this model run well on this device?" classification (ADR-002:
/// device tiering lives in `core/`, one place — not scattered per-feature
/// heuristics). No I/O; callers supply the RAM reading from
/// [DeviceInfoService].
library;

/// Verdict shown next to a model/quant in the hub UI.
enum ModelTier {
  /// Comfortable headroom above the class floor.
  comfortable,

  /// Meets the class floor but with little headroom — may be slow or evict
  /// other apps from memory.
  possible,

  /// Below the class floor. Loading may OOM.
  notRecommended,
}

/// RAM floor, in GiB (binary gigabytes — matches how DECISIONS.md states
/// device RAM specs), per size class. Anchors from orchestra/DECISIONS.md
/// (DEVICE FLOOR) and orchestra/research/hf-api.md §6: 1B-class Q4 GGUFs
/// (~0.7-1.1GB files) want 4GB+ RAM; 3-4B-class (~1.9-2.4GB files) want
/// 6GB+; anything larger is extrapolated to 8GB+ per the same table's 4B+
/// row. Boundaries are file-size buckets because quantized file size tracks
/// parameter count closely enough to classify by size alone; `quant` is
/// accepted for the UI's own display/logging and future refinement (e.g. a
/// f16 file of the same size decodes slower than a Q4 file) but does not
/// currently change the verdict.
const _class1BMaxBytes = 1258291200; // 1.2 GiB
const _class3BMaxBytes = 3221225472; // 3 GiB
const _floor1BBytes = 4294967296; // 4 GiB
const _floor3BBytes = 6442450944; // 6 GiB
const _floor4BPlusBytes = 8589934592; // 8 GiB

/// Headroom multiplier above the floor to call a device "comfortable"
/// rather than merely "possible".
const _comfortableMultiplier = 1.5;

/// Classify how well [fileSizeBytes] (the GGUF file size for the quant the
/// user is looking at) will run given [totalRamBytes] of device RAM.
///
/// [mmprojSizeBytes] adds a vision model's mmproj projector footprint to the
/// verdict (both load into memory together — Loop-7 T1's
/// `EngineLoadParams.mmprojPath`) — e.g. a 416MB model + 103MB projector is
/// classified as a ~519MB combined footprint, not 416MB alone. Defaults to 0
/// for a plain text model.
ModelTier classifyModelTier({
  required int fileSizeBytes,
  required int totalRamBytes,
  String? quant,
  int mmprojSizeBytes = 0,
}) {
  final floor = ramFloorBytesFor(fileSizeBytes + mmprojSizeBytes);
  if (totalRamBytes < floor) return ModelTier.notRecommended;
  if (totalRamBytes < floor * _comfortableMultiplier) return ModelTier.possible;
  return ModelTier.comfortable;
}

/// The RAM floor (bytes) [classifyModelTier] applies for a GGUF of
/// [fileSizeBytes]. Public so UI can build the verdict chip's one-line
/// explanation ("needs ~6GB RAM, you have 8GB") without duplicating the
/// size-class bucket table.
int ramFloorBytesFor(int fileSizeBytes) {
  if (fileSizeBytes <= _class1BMaxBytes) return _floor1BBytes;
  if (fileSizeBytes <= _class3BMaxBytes) return _floor3BBytes;
  return _floor4BPlusBytes;
}

const _gibBytes = 1024 * 1024 * 1024;

/// Recovers a device's *nominal* RAM capacity from the OS-reported physical
/// RAM, for use as [classifyModelTier]'s `totalRamBytes`.
///
/// `ActivityManager.totalMem` / `NSProcessInfo.physicalMemory` report LESS than
/// the marketed capacity — the kernel and reserved (GPU/DMA) carve-outs eat
/// ~5-20% — so a nominal 4GB phone reads only ~3.6-3.9 GiB. The floors above
/// are written against MARKETED capacity (DECISIONS.md "1B → 4GB"), so a raw
/// reading sits just under its own floor and classifies EVERY model
/// `notRecommended`. Round the reading up to the next whole GiB to undo the
/// carve-out and land back on the marketed tier (4/6/8/12 GiB).
// ponytail: whole-GiB ceil recovers the standard tiers; only needs a real
// nominal-capacity table if a device's carve-out ever exceeds ~1 GiB.
int nominalRamBytes(int reportedBytes) {
  if (reportedBytes <= 0) return reportedBytes;
  return ((reportedBytes + _gibBytes - 1) ~/ _gibBytes) * _gibBytes;
}
