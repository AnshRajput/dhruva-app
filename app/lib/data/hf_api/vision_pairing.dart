/// Pure vision-model detection + mmproj projector pairing. No I/O — operates
/// on an already-fetched [HfRepoFile] list (see `HfApiClient.getRepoFiles`).
library;

import 'models/hf_repo_file.dart';
import 'quant_parser.dart';

/// True when [path]'s basename is an mtmd projector file: starts with
/// "mmproj" (case-insensitive) and ends in ".gguf". Confirmed HF convention
/// (Loop-7 PLAN, orchestra/BLACKBOARD.md): the projector ships in the SAME
/// repo as its paired vision model, sometimes under a `mmproj/` subfolder —
/// already flattened into [HfRepoFile.path] by `HfApiClient._walkTree`,
/// which is why only the basename is checked here.
bool isMmprojFile(String path) {
  final base = _basename(path).toLowerCase();
  return base.startsWith('mmproj') && base.endsWith('.gguf');
}

String _basename(String path) {
  final idx = path.lastIndexOf('/');
  return idx == -1 ? path : path.substring(idx + 1);
}

/// Picks the best mmproj projector for [modelFile] out of [mmprojFiles]
/// (every mmproj-named file in the same repo — see [isMmprojFile]).
///
/// Matching rule, in order:
/// 1. Same quant token as [modelFile] (e.g. a `Q8_0` model pairs with
///    `mmproj-<name>-Q8_0.gguf`) — mtmd decodes the projector at its own
///    stated precision, not the model's, so an exact label match is the
///    correct pairing whenever the repo publishes one.
/// 2. Else the smallest F16 projector, if any exist — mtmd's own
///    highest-fidelity default and a safe choice when no quant-matched
///    projector is published.
/// 3. Else the smallest mmproj file overall — minimizes the extra footprint
///    for a fallback pairing.
///
/// Returns null when [mmprojFiles] is empty (a text-only model in this
/// repo).
HfRepoFile? matchMmprojFor(HfRepoFile modelFile, List<HfRepoFile> mmprojFiles) {
  if (mmprojFiles.isEmpty) return null;
  final modelQuant = extractQuantVariant(modelFile.path);
  if (modelQuant != null) {
    for (final candidate in mmprojFiles) {
      if (extractQuantVariant(candidate.path) == modelQuant) return candidate;
    }
  }
  final f16Candidates = mmprojFiles.where(
    (f) => extractQuantVariant(f.path) == 'F16',
  );
  final pool = f16Candidates.isNotEmpty ? f16Candidates : mmprojFiles;
  return pool.reduce((a, b) => a.sizeBytes <= b.sizeBytes ? a : b);
}
