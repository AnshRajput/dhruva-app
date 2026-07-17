// Character create/edit form: live validation (name+persona required, Save
// disabled until both are filled), Save calls the repository (create for a
// new character, updateCharacter for an existing one), and built-in
// characters render the "can't edit, duplicate instead" blocked view.

import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/characters/character_repository.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/features/characters/ui/character_form_screen.dart';
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
    String persona = 'Be encouraging.',
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

  // A root screen sits under every push in these tests, matching the real
  // app (the form is always *pushed* on top of a gallery/detail screen) —
  // `context.pop()` on save-while-editing needs something to pop back to,
  // which a bare `initialLocation` at the form route itself wouldn't have.
  Widget buildApp({int? characterId}) {
    final router = GoRouter(
      initialLocation: '/characters',
      routes: [
        GoRoute(
          path: '/characters',
          builder: (context, state) => Builder(
            builder: (context) => TextButton(
              onPressed: () => context.push(
                characterId == null
                    ? '/characters/new'
                    : '/characters/$characterId/edit',
              ),
              child: const Text('open form'),
            ),
          ),
        ),
        GoRoute(
          path: '/characters/new',
          builder: (context, state) => const CharacterFormScreen(),
        ),
        GoRoute(
          path: '/characters/:id/edit',
          builder: (context, state) => CharacterFormScreen(
            characterId: int.parse(state.pathParameters['id']!),
          ),
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
        // No starter-pack seeding here — these tests assert exact row
        // counts/content, and seeding is a real asset read racing against
        // the test's own timeline (see CharacterRepository's own tests for
        // the `starterPackLoader: () async => null` precedent).
        characterRepositoryProvider.overrideWithValue(
          CharacterRepository(db: db, starterPackLoader: () async => null),
        ),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    );
  }

  Future<void> openForm(WidgetTester tester) async {
    await tester.tap(find.text('open form'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Save is disabled until both name and persona are filled in (live '
    'validation)',
    (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      await openForm(tester);

      TextButton saveButton() =>
          tester.widget<TextButton>(find.widgetWithText(TextButton, 'Save'));
      expect(saveButton().onPressed, isNull);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name'),
        'Coach',
      );
      await tester.pump();
      expect(saveButton().onPressed, isNull); // persona still empty

      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Be an encouraging coach.',
      );
      await tester.pump();
      expect(saveButton().onPressed, isNotNull);
    },
  );

  testWidgets('Save on a new character calls createCharacter via the '
      'repository (persisted row appears)', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await openForm(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Coach');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Be an encouraging coach.',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.characters).get();
    expect(rows, hasLength(1));
    expect(rows.single.name, 'Coach');
    expect(rows.single.personaSystemPrompt, 'Be an encouraging coach.');
    // Save on create navigates to the new character's detail route.
    expect(find.text('detail:${rows.single.id}'), findsOneWidget);
  });

  testWidgets('Save on an existing character calls updateCharacter, not '
      'create (no duplicate row)', (tester) async {
    final id = await insertCharacter();
    await tester.pumpWidget(buildApp(characterId: id));
    await tester.pumpAndSettle();
    await openForm(tester);

    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Be a VERY intense coach.',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.characters).get();
    expect(rows, hasLength(1));
    expect(rows.single.personaSystemPrompt, 'Be a VERY intense coach.');
  });

  testWidgets(
    'a built-in character shows the "can\'t edit directly" blocked view '
    'with a duplicate-to-edit affordance instead of the form',
    (tester) async {
      final id = await insertCharacter(name: 'Coach', isBuiltIn: true);
      await tester.pumpWidget(buildApp(characterId: id));
      await tester.pumpAndSettle();
      await openForm(tester);

      expect(
        find.text("Built-in characters can't be edited directly."),
        findsOneWidget,
      );
      expect(find.text('Duplicate to edit'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Name'), findsNothing);
    },
  );
}
