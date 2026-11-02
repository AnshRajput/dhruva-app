import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/engine_bindings/fake_engine_service.dart';
import 'package:dhruva/features/chat/ui/conversation_list_screen.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _fakeDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertModel() {
    return db
        .into(db.installedModels)
        .insert(
          InstalledModelsCompanion.insert(
            repoId: 'org/Model-GGUF',
            fileName: 'model.gguf',
            sizeBytes: 100,
            localPath: '/tmp/dhruva-list-test.gguf',
            downloadedAt: DateTime.utc(2026, 7, 17),
          ),
        );
  }

  Widget buildApp() {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const ConversationListScreen(),
        ),
        GoRoute(
          path: '/chat/:id',
          builder: (context, state) =>
              Text('thread:${state.pathParameters['id']}'),
        ),
        GoRoute(
          path: '/models/hub',
          builder: (context, state) => const Text('models hub'),
        ),
        GoRoute(
          path: '/actions',
          builder: (context, state) => const Text('actions stand-in'),
        ),
        GoRoute(
          path: '/personas',
          builder: (context, state) => const Text('personas stand-in'),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
        engineServiceProvider.overrideWithValue(FakeEngineService()),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    );
  }

  testWidgets('no model installed shows the no-model empty state', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('No model installed yet'), findsOneWidget);
  });

  testWidgets(
    'model installed, no conversations shows the no-conversations empty state',
    (tester) async {
      await insertModel();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Start your first conversation'), findsOneWidget);
    },
  );

  testWidgets('conversations render pinned-first with folder chips', (
    tester,
  ) async {
    await insertModel();
    final repo = db;
    final folderId = await repo
        .into(repo.folders)
        .insert(const FoldersCompanion(name: Value('Work')));
    final a = await repo
        .into(repo.conversations)
        .insert(
          ConversationsCompanion.insert(
            title: const Value('Alpha'),
            createdAt: DateTime.utc(2026, 7, 17),
            updatedAt: DateTime.utc(2026, 7, 17),
          ),
        );
    await repo
        .into(repo.conversations)
        .insert(
          ConversationsCompanion.insert(
            title: const Value('Beta'),
            folderId: Value(folderId),
            createdAt: DateTime.utc(2026, 7, 17),
            updatedAt: DateTime.utc(2026, 7, 17),
          ),
        );
    await (repo.update(repo.conversations)..where((t) => t.id.equals(a))).write(
      const ConversationsCompanion(pinned: Value(true)),
    );

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
  });

  testWidgets(
    'FAB with exactly one installed model creates a draft chat and navigates',
    (tester) async {
      await insertModel();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('thread:new'), findsOneWidget);
    },
  );

  testWidgets(
    'no model and no chats: one "get a model" screen with none of the chat '
    'chrome, and its button routes to Models',
    (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('No model installed yet'), findsOneWidget);
      // Nothing that cannot work yet: no New chat button, folders, quick
      // actions or Talk. The Actions / Personas doors stay.
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('All'), findsNothing);
      expect(find.text('Quick actions'), findsNothing);
      expect(find.text('Talk'), findsNothing);
      expect(find.byTooltip('Actions'), findsOneWidget);

      await tester.tap(find.text('Browse models'));
      await tester.pumpAndSettle();
      expect(find.text('models hub'), findsOneWidget);
    },
  );

  testWidgets(
    'search icon opens search; shows snippet, opens chat, empty state',
    (tester) async {
      await insertModel();
      final id = await db
          .into(db.conversations)
          .insert(
            ConversationsCompanion.insert(
              title: const Value('Trip planning'),
              createdAt: DateTime.utc(2026, 7, 17),
              updatedAt: DateTime.utc(2026, 7, 17),
            ),
          );
      await db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              conversationId: id,
              role: MessageRole.user,
              status: MessageStatus.complete,
              content: const Value('Which hotel near the Louvre is best?'),
              createdAt: DateTime.utc(2026, 7, 17),
            ),
          );
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Search chats'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'louvre');
      await tester.pump(const Duration(milliseconds: 300)); // debounce
      await tester.pumpAndSettle();
      expect(find.textContaining('hotel near the Louvre'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'zzzz-nothing');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('No chats match'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'trip');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trip planning'));
      await tester.pumpAndSettle();
      expect(find.text('thread:$id'), findsOneWidget);
    },
  );

  testWidgets('Actions and Personas are labelled entry points, not bare '
      'icons, and still carry tooltips', (tester) async {
    await insertModel();
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    // Visible text labels (a chip's label is real text, not just a tooltip).
    final actions = find.widgetWithText(ActionChip, 'Actions');
    final personas = find.widgetWithText(ActionChip, 'Personas');
    expect(actions, findsOneWidget);
    expect(personas, findsOneWidget);
    expect(find.byTooltip('Actions'), findsOneWidget);
    expect(find.byTooltip('Personas'), findsOneWidget);
    // The old icon-only app-bar buttons are gone.
    expect(
      find.widgetWithIcon(IconButton, Icons.auto_awesome_outlined),
      findsNothing,
    );
    expect(
      find.widgetWithIcon(IconButton, Icons.theater_comedy_outlined),
      findsNothing,
    );

    await tester.tap(personas);
    await tester.pumpAndSettle();
    expect(find.text('personas stand-in'), findsOneWidget);
  });

  testWidgets('the entry points also show on a narrow phone with big text', (
    tester,
  ) async {
    await insertModel();
    await tester.binding.setSurfaceSize(const Size(300, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(ActionChip, 'Actions'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Personas'), findsOneWidget);
  });
}
