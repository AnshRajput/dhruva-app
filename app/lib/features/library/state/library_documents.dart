/// The Library's Documents list: files attached to chats and files of the
/// connected folder in one list, newest first.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/connector_providers.dart';
import '../../../core/di/library_providers.dart';
import '../../../data/connectors/connector_store.dart' show FolderFile;
import '../../../data/docs/document_repository.dart' show DocumentInfo;
import 'library_text.dart';

/// A file in the connected folder, as the Library's sheets need it.
final class LibraryFile {
  final String fileId;
  final String name;
  final int itemId;
  final int? pages;
  final DateTime? modified;

  /// Why it cannot be searched, or null.
  final String? problem;
  const LibraryFile({
    required this.fileId,
    required this.name,
    required this.itemId,
    this.pages,
    this.modified,
    this.problem,
  });

  factory LibraryFile.of(FolderFile f) => LibraryFile(
    fileId: f.fileId,
    name: f.name,
    itemId: f.itemId,
    pages: f.pages,
    modified: f.modified,
    problem: f.problem,
  );
}

final class LibraryDocEntry {
  final String key;
  final String name;
  final String badge;
  final String detail;
  final DateTime? at;

  /// Set for a document attached to a chat: tapping opens that chat.
  final int? conversationId;

  /// Set for a folder file: tapping opens its sheet.
  final LibraryFile? file;

  const LibraryDocEntry({
    required this.key,
    required this.name,
    required this.badge,
    required this.detail,
    required this.at,
    this.conversationId,
    this.file,
  });
}

/// One document, one row. An attached file and its folder copy are the same
/// document, and so is a file attached to two chats: same name (any case) and,
/// where both sides know it, the same page count. The newest attachment wins.
/// Neither record carries a content hash or the source URI, so name + pages is
/// the identity the data offers today.
/// ponytail: switch to a content hash when the stores keep one.
List<DocumentInfo> dedupeAttached(
  List<DocumentInfo> docs,
  List<FolderFile> folderFiles,
) {
  String norm(String n) => n.trim().toLowerCase();
  bool sameFile(DocumentInfo d, FolderFile f) =>
      norm(d.name) == norm(f.name) &&
      (f.pages == null || d.pageCount <= 0 || f.pages == d.pageCount);
  final out = <DocumentInfo>[];
  for (final d in [
    ...docs,
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt))) {
    if (folderFiles.any((f) => sameFile(d, f))) continue;
    final repeat = out.any(
      (o) =>
          norm(o.name) == norm(d.name) &&
          (o.pageCount <= 0 || d.pageCount <= 0 || o.pageCount == d.pageCount),
    );
    if (!repeat) out.add(d);
  }
  return out;
}

final libraryDocumentsProvider = Provider<AsyncValue<List<LibraryDocEntry>>>((
  ref,
) {
  final docs = ref.watch(allDocumentsProvider);
  final files = ref.watch(folderFilesProvider);
  final error = docs.error ?? files.error;
  if (error != null && !docs.hasValue && !files.hasValue) {
    return AsyncError(error, StackTrace.current);
  }
  if (!docs.hasValue && !files.hasValue) return const AsyncLoading();
  final now = DateTime.now();
  final folderFiles = files.value ?? const <FolderFile>[];
  final attached = dedupeAttached(
    docs.value ?? const <DocumentInfo>[],
    folderFiles,
  );
  final out = <LibraryDocEntry>[
    for (final d in attached)
      LibraryDocEntry(
        key: 'doc-${d.id}',
        name: d.name,
        badge: fileBadge(d.name),
        detail: d.paged
            ? '${d.pageCount} ${d.pageCount == 1 ? 'page' : 'pages'} · attached to Ask'
            : 'attached to Ask',
        at: d.createdAt,
        conversationId: d.conversationId,
      ),
    for (final f in folderFiles)
      LibraryDocEntry(
        key: 'file-${f.fileId}',
        name: f.name,
        badge: fileBadge(f.name),
        detail: f.ready
            ? 'Notes${f.modified == null ? '' : ' · changed ${changedAgo(f.modified!, now)}'}'
            : unreadableReason(f.problem!),
        at: f.modified,
        file: LibraryFile.of(f),
      ),
  ];
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  out.sort((a, b) => (b.at ?? epoch).compareTo(a.at ?? epoch));
  return AsyncData(out);
});
