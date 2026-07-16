import 'package:freezed_annotation/freezed_annotation.dart';

part 'hf_repo_file.freezed.dart';

/// One file entry from a repo's `/tree/main` listing (recursed into
/// subfolders — see `HfApiClient.getRepoFiles`). Directory entries are
/// walked, not represented here.
@freezed
abstract class HfRepoFile with _$HfRepoFile {
  const factory HfRepoFile({
    /// Full path within the repo, including subfolder prefix (e.g.
    /// `"mmproj/mmproj-Q8_0.gguf"`).
    required String path,
    required int sizeBytes,

    /// `lfs.oid` when the tree entry carries a `sha256:`-prefixed oid;
    /// null for non-LFS files or when the API omits it.
    String? sha256,
  }) = _HfRepoFile;
}
