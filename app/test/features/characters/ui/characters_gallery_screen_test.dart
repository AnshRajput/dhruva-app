// Characters gallery: built-ins + user characters render (with a "Built-in"
// marker distinguishing them), the empty state shows when there are none,
// "+ Create" and tapping a tile navigate to the right routes.

import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/characters/character_repository.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/features/characters/ui/characters_gallery_screen.dart';
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
    required String name,
    bool isBuiltIn = false,
    String persona = 'Be helpful.',
  }) {
    final now = DateTime.now();
    return db
        .into(db.characters)
        .insert(
          CharactersCompanion.insert(
            name: name,
            personaSystemPrompt: persona,
            isBuiltIn: Value(isBuiltIn),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Widget buildApp() {
    final router = GoRouter(
      initialLocation: '/characters',
      routes: [
        GoRoute(
          path: '/characters',
          builder: (context, state) => const CharactersGalleryScreen(),
        ),
        GoRoute(
          path: '/characters/new',
          builder: (context, state) => const Text('new character form'),
        ),
        GoRoute(
          path: '/characters/:id',
          builder: (context, state) =>
              Text('detail:${state.pathParameters['id']}'),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        // No starter-pack seeding — these tests assert exact
        // presence/absence, and seeding is a real asset read racing
        // against the test's own timeline.
        characterRepositoryProvider.overrideWithValue(
          CharacterRepository(db: db, starterPackLoader: () async => null),
        ),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    );
  }

  testWidgets(
    'built-in characters render in the grid with a "Built-in" marker; user '
    'characters render without one',
    (tester) async {
      await insertCharacter(name: 'Coach', isBuiltIn: true);
      await insertCharacter(name: 'My Own Character', isBuiltIn: false);

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Coach'), findsOneWidget);
      expect(find.text('My Own Character'), findsOneWidget);
      expect(find.text('Built-in'), findsOneWidget);
    },
  );

  testWidgets('empty state shows a create CTA when there are no characters', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('No characters yet'), findsOneWidget);
    expect(find.text('Create a character'), findsOneWidget);
  });

  testWidgets('the "+ Create" FAB navigates to /characters/new', (
    tester,
  ) async {
    await insertCharacter(name: 'Coach');
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Create'));
    await tester.pumpAndSettle();

    expect(find.text('new character form'), findsOneWidget);
  });

  testWidgets('tapping a character tile navigates to its detail route', (
    tester,
  ) async {
    final id = await insertCharacter(name: 'Coach');
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Coach'));
    await tester.pumpAndSettle();

    expect(find.text('detail:$id'), findsOneWidget);
  });
}
