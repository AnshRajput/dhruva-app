import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/data/chat/chat_repository.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/features/chat/state/conversation_list_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ChatRepository repo;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ChatRepository(db: db);
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'build() lists conversations pinned-first, straight from the repo',
    () async {
      final a = await repo.createConversation(title: 'A');
      final b = await repo.createConversation(title: 'B');
      await repo.setPinned(b, true);

      final state = await container.read(
        conversationListControllerProvider.future,
      );
      expect(state.conversations.map((c) => c.id), [b, a]);
    },
  );

  test('selectFolder scopes the conversation list', () async {
    final folderId = await repo.createFolder('Work');
    final inFolder = await repo.createConversation(
      title: 'in',
      folderId: folderId,
    );
    await repo.createConversation(title: 'out');
    await container.read(conversationListControllerProvider.future);

    await container
        .read(conversationListControllerProvider.notifier)
        .selectFolder(folderId);

    final state = container.read(conversationListControllerProvider).value!;
    expect(state.conversations.map((c) => c.id), [inFolder]);
    expect(state.selectedFolderId, folderId);
  });

  test(
    'search populates searchResults and isSearching, empty query clears it',
    () async {
      final id = await repo.createConversation(title: 'hello world');
      await container.read(conversationListControllerProvider.future);

      await container
          .read(conversationListControllerProvider.notifier)
          .search('hello');
      var state = container.read(conversationListControllerProvider).value!;
      expect(state.isSearching, isTrue);
      expect(state.searchResults.single.conversationId, id);

      await container
          .read(conversationListControllerProvider.notifier)
          .search('');
      state = container.read(conversationListControllerProvider).value!;
      expect(state.isSearching, isFalse);
      expect(state.searchResults, isEmpty);
    },
  );

  test('setPinned/rename/moveToFolder/delete mutate and refresh', () async {
    final folderId = await repo.createFolder('Work');
    final id = await repo.createConversation(title: 'x');
    await container.read(conversationListControllerProvider.future);
    final notifier = container.read(
      conversationListControllerProvider.notifier,
    );

    await notifier.setPinned(id, true);
    expect(
      container
          .read(conversationListControllerProvider)
          .value!
          .conversations
          .single
          .pinned,
      isTrue,
    );

    await notifier.rename(id, 'renamed');
    expect(
      container
          .read(conversationListControllerProvider)
          .value!
          .conversations
          .single
          .title,
      'renamed',
    );

    await notifier.moveToFolder(id, folderId);
    expect(
      container
          .read(conversationListControllerProvider)
          .value!
          .conversations
          .single
          .folderId,
      folderId,
    );

    await notifier.delete(id);
    expect(
      container.read(conversationListControllerProvider).value!.conversations,
      isEmpty,
    );
  });

  test('a failed action sets actionError instead of throwing', () async {
    await container.read(conversationListControllerProvider.future);
    final notifier = container.read(
      conversationListControllerProvider.notifier,
    );

    await notifier.rename(999, 'nope');

    final state = container.read(conversationListControllerProvider).value!;
    expect(state.actionError, isNotNull);
  });

  test('createFolder adds a folder visible in the next build', () async {
    await container.read(conversationListControllerProvider.future);
    await container
        .read(conversationListControllerProvider.notifier)
        .createFolder('Ideas');

    final state = container.read(conversationListControllerProvider).value!;
    expect(state.folders.map((f) => f.name), contains('Ideas'));
  });
}
