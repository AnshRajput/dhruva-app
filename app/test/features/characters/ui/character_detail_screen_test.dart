// Character detail: full persona view, "Chat with {name}" navigates to a
// character-bound draft (proving the wiring end-to-end from detail screen
// -> router -> ChatRouteArgs.characterId — the actual persona-reaches-the-
// engine proof lives in chat_controller_test.dart's Loop 5 group, which
// exercises ChatController._buildFromCharacter directly), Edit/Delete for
// user characters, Duplicate for built-ins, and the export affordance's two
// format options.

import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/characters/character_repository.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/features/characters/ui/character_detail_screen.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertCharacter({
    String name = 'Coach',
    bool isBuiltIn = false,
    String persona = 'Be an encouraging coach.',
    String? greeting,
  }) {
    final now = DateTime.now();
    return db
        .into(db.characters)
        .insert(
          CharactersCompanion.insert(
            name: name,
            personaSystemPrompt: persona,
            greeting: Value(greeting),
            isBuiltIn: Value(isBuiltIn),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Widget buildApp(int characterId) {
    final router = GoRouter(
      initialLocation: '/characters',
      routes: [
        GoRoute(
          path: '/characters',
          builder: (context, state) => Builder(
            builder: (context) => TextButton(
              onPressed: () => context.push('/characters/$characterId'),
              child: const Text('open detail'),
            ),
          ),
        ),
        GoRoute(
          path: '/characters/:id',
          builder: (context, state) => CharacterDetailScreen(
            characterId: int.parse(state.pathParameters['id']!),
          ),
        ),
        GoRoute(
          path: '/characters/:id/edit',
          builder: (context, state) =>
              Text('edit:${state.pathParameters['id']}'),
        ),
        GoRoute(
          path: '/chat/:id',
          builder: (context, state) => Text('chat location: ${state.uri}'),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        characterRepositoryProvider.overrideWithValue(
          CharacterRepository(db: db, starterPackLoader: () async => null),
        ),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    );
  }

  Future<void> openDetail(WidgetTester tester) async {
    await tester.tap(find.text('open detail'));
    await tester.pumpAndSettle();
  }

  testWidgets('renders the persona, greeting, and a "Chat with" CTA', (
    tester,
  ) async {
    final id = await insertCharacter(greeting: 'Ready to crush it today?');
    await tester.pumpWidget(buildApp(id));
    await tester.pumpAndSettle();
    await openDetail(tester);

    expect(find.text('Coach'), findsWidgets);
    expect(find.text('Be an encouraging coach.'), findsOneWidget);
    expect(find.text('Ready to crush it today?'), findsOneWidget);
    expect(find.text('Chat with Coach'), findsOneWidget);
  });

  testWidgets('"Chat with {name}" navigates to a new character-bound draft '
      '(characterId in the query string)', (tester) async {
    final id = await insertCharacter();
    await tester.pumpWidget(buildApp(id));
    await tester.pumpAndSettle();
    await openDetail(tester);

    await tester.tap(find.text('Chat with Coach'));
    await tester.pumpAndSettle();

    expect(find.textContaining('/chat/new?characterId=$id'), findsOneWidget);
  });

  testWidgets('a user (non-built-in) character offers Edit and Delete via the '
      'overflow menu, not Duplicate', (tester) async {
    final id = await insertCharacter();
    await tester.pumpWidget(buildApp(id));
    await tester.pumpAndSettle();
    await openDetail(tester);

    expect(find.byIcon(Icons.copy_all_outlined), findsNothing);
    await tester.tap(find.byWidgetPredicate((w) => w is PopupMenuButton));
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('a built-in character offers Duplicate instead of Edit/Delete', (
    tester,
  ) async {
    final id = await insertCharacter(isBuiltIn: true);
    await tester.pumpWidget(buildApp(id));
    await tester.pumpAndSettle();
    await openDetail(tester);

    expect(find.byTooltip('Duplicate to edit'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is PopupMenuButton), findsNothing);
  });

  testWidgets('deleting a character removes it and pops back', (tester) async {
    final id = await insertCharacter();
    await tester.pumpWidget(buildApp(id));
    await tester.pumpAndSettle();
    await openDetail(tester);

    await tester.tap(find.byWidgetPredicate((w) => w is PopupMenuButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.characters).get();
    expect(rows, isEmpty);
    // Popped back to the "open detail" button screen.
    expect(find.text('open detail'), findsOneWidget);
  });

  testWidgets('the export affordance offers both JSON and PNG card formats', (
    tester,
  ) async {
    final id = await insertCharacter();
    await tester.pumpWidget(buildApp(id));
    await tester.pumpAndSettle();
    await openDetail(tester);

    await tester.tap(find.byTooltip('Export'));
    await tester.pumpAndSettle();

    expect(find.text('Export as JSON card'), findsOneWidget);
    expect(find.text('Export as PNG card'), findsOneWidget);
  });
}
