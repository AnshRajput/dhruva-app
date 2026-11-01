/// Riverpod surface of the Library (saved answers, to-dos, attached
/// documents). Tests override [appDatabaseProvider] with an in-memory DB.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/docs/document_repository.dart';
import '../../data/library/library_store.dart';
import 'providers.dart';

final libraryStoreProvider = Provider<LibraryStore>(
  (ref) => LibraryStore(db: ref.watch(appDatabaseProvider)),
);

/// Saved replies, newest first.
final savedAnswersProvider = StreamProvider<List<SavedAnswer>>(
  (ref) => ref.watch(libraryStoreProvider).watchSaved(),
);

/// To-dos: open first, then done.
final todosProvider = StreamProvider<List<TodoItem>>(
  (ref) => ref.watch(libraryStoreProvider).watchTodos(),
);

/// Documents attached to chats, newest first.
final allDocumentsProvider = StreamProvider<List<DocumentInfo>>(
  (ref) => ref.watch(documentRepositoryProvider).watchAllDocuments(),
);
