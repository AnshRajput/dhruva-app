import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/chat/chat_repository.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/features/chat/state/conversation_list_controller.dart';
import 'package:dhruva/features/chat/widgets/conversation_tile.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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

  Widget buildApp(ConversationSummary conversation, List<FolderInfo> folders) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: ConversationTile(
              conversation: conversation,
              folders: folders,
            ),
          ),
        ),
        GoRoute(
          path: '/chat/:id',
          builder: (context, state) => const Text('thread'),
        ),
      ],
    );
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    );
  }

  testWidgets('pin toggles pinned state', (tester) async {
    final id = await repo.createConversation(title: 'Alpha');
    await container.read(conversationListControllerProvider.future);
    final convo = (await repo.getConversation(id))!;

    await tester.pumpWidget(buildApp(convo, const []));
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin'));
    await tester.pumpAndSettle();

    expect((await repo.getConversation(id))!.pinned, isTrue);
  });

  testWidgets('rename persists the new title', (tester) async {
    final id = await repo.createConversation(title: 'Alpha');
    await container.read(conversationListControllerProvider.future);
    final convo = (await repo.getConversation(id))!;

    await tester.pumpWidget(buildApp(convo, const []));
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Renamed');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect((await repo.getConversation(id))!.title, 'Renamed');
  });

  testWidgets('move to folder persists folderId', (tester) async {
    final folderId = await repo.createFolder('Work');
    final id = await repo.createConversation(title: 'Alpha');
    await container.read(conversationListControllerProvider.future);
    final convo = (await repo.getConversation(id))!;
    final folders = await repo.listFolders();

    await tester.pumpWidget(buildApp(convo, folders));
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to folder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();

    expect((await repo.getConversation(id))!.folderId, folderId);
  });

  testWidgets('delete via menu removes the conversation after confirmation', (
    tester,
  ) async {
    final id = await repo.createConversation(title: 'Alpha');
    await container.read(conversationListControllerProvider.future);
    final convo = (await repo.getConversation(id))!;

    await tester.pumpWidget(buildApp(convo, const []));
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last); // confirm dialog button
    await tester.pumpAndSettle();

    expect(await repo.getConversation(id), isNull);
  });

  testWidgets('tapping the tile navigates to the thread route', (tester) async {
    final id = await repo.createConversation(title: 'Alpha');
    await container.read(conversationListControllerProvider.future);
    final convo = (await repo.getConversation(id))!;

    await tester.pumpWidget(buildApp(convo, const []));
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    expect(find.text('thread'), findsOneWidget);
  });
}
