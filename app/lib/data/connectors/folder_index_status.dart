/// How far the connected folder's index has got, in the plain words the
/// Library and the Connectors screen both show ("312 of 340 files ready ·
/// finishes while charging").
library;

import 'connector_store.dart' show FolderFile;

final class FolderIndexStatus {
  /// Files whose text is searchable.
  final int ready;

  /// Files the index could not read (too large, scanned, unreadable): they
  /// will not become searchable, so they are not "still to do".
  final int unreadable;

  /// Files the folder holds, as of the last listing. Null before the first
  /// sync has listed it.
  final int? total;

  const FolderIndexStatus({
    required this.ready,
    required this.unreadable,
    required this.total,
  });

  factory FolderIndexStatus.of(List<FolderFile> files, {int? total}) =>
      FolderIndexStatus(
        ready: files.where((f) => f.ready).length,
        unreadable: files.where((f) => !f.ready).length,
        total: total,
      );

  /// Files still waiting for their turn.
  int get remaining {
    final t = total;
    if (t == null) return 0;
    final left = t - ready - unreadable;
    return left < 0 ? 0 : left;
  }

  bool get isComplete => total != null && remaining == 0;

  /// 0..1 for a progress bar; null when the total is not known yet.
  double? get fraction {
    final t = total;
    if (t == null || t <= 0) return null;
    return ((ready + unreadable) / t).clamp(0.0, 1.0);
  }

  /// "312 of 340 files ready to search". [indexing] is true while a run is
  /// in progress.
  String headline() {
    final t = total;
    if (t == null) {
      return ready == 0
          ? 'Not indexed yet'
          : '$ready ${_files(ready)} ready to search';
    }
    if (t == 0) return 'No files found in this folder';
    if (remaining == 0 && unreadable == 0) {
      return 'All $t ${_files(t)} ready to search';
    }
    return '$ready of $t ${_files(t)} ready to search';
  }

  /// The second half of the line: what happens next.
  String detail({required bool indexing}) {
    if (indexing) return 'Indexing now';
    if (remaining > 0) return 'Finishes while charging';
    if (unreadable > 0) {
      return '$unreadable can\'t be searched (too large, scanned or locked)';
    }
    return 'Up to date';
  }
}

String _files(int n) => n == 1 ? 'file' : 'files';
