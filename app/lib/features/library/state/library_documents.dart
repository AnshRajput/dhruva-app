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
  final out = <LibraryDocEntry>[
    for (final d in docs.value ?? const <DocumentInfo>[])
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
    for (final f in files.value ?? const <FolderFile>[])
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
