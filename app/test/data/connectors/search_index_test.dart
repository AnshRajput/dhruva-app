import 'package:dhruva/data/connectors/connector.dart';
import 'package:dhruva/data/connectors/connector_store.dart';
import 'package:dhruva/data/connectors/search_index.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The same behavioural suite runs against both engines.
  for (final forceFallback in [false, true]) {
    group(forceFallback ? 'BM25 fallback' : 'FTS5', () {
      late AppDatabase db;
      late ConnectorStore store;
      late SearchIndex index;

      setUp(() async {
        db = AppDatabase(NativeDatabase.memory());
        store = ConnectorStore(
          db: db,
          clock: () => DateTime.utc(2026, 11, 1, 8),
        );
        index = await openSearchIndex(db, store, forceFallback: forceFallback);
        await store.upsertItems('calendar', [
          ItemDraft(
            externalId: 'e1',
            kind: ItemKind.event,
            title: 'Budget review with Ravi',
            body: 'Quarterly budget numbers, headcount plan',
            startsAt: DateTime.utc(2026, 11, 2, 10),
          ),
          ItemDraft(
            externalId: 'e2',
            kind: ItemKind.event,
            title: 'Dentist',
            body: 'Bring insurance card',
            startsAt: DateTime.utc(2026, 11, 3, 10),
          ),
        ]);
        await store.upsertItems('folder', [
          const ItemDraft(
            externalId: 'f1',
            kind: ItemKind.file,
            title: 'notes.md',
            body:
                'Budget budget budget. The budget for the trip to Pune is '
                'tight; hotel prices are up.',
          ),
          const ItemDraft(
            externalId: 'f2',
            kind: ItemKind.file,
            title: 'recipes.txt',
            body: 'Dal tadka: onion, tomato, garlic, cumin.',
          ),
        ]);
        await store.upsertItems('notifications', [
          const ItemDraft(
            externalId: 'n1',
            kind: ItemKind.notification,
            title: 'Ravi',
            body: 'Can you send the budget file?',
          ),
        ]);
      });
      tearDown(() => db.close());

      test('engine is chosen as asked', () {
        expect(index.engine, forceFallback ? 'bm25' : 'fts5');
      });

      test('ranks the best match first (title + frequency)', () async {
        final hits = await index.search('budget');
        expect(hits, isNotEmpty);
        // The title hit and the repeated-term body both outrank the one-word
        // notification; the unrelated items never appear.
        final ids = hits.map((h) => h.item.externalId).toList();
        expect(ids, containsAll(['e1', 'f1', 'n1']));
        expect(ids, isNot(contains('e2')));
        expect(ids, isNot(contains('f2')));
        expect(ids.last, 'n1');
        for (var i = 1; i < hits.length; i++) {
          expect(hits[i - 1].score, greaterThanOrEqualTo(hits[i].score));
        }
      });

      test('stopwords-only and empty queries return nothing', () async {
        expect(await index.search('the of and'), isEmpty);
        expect(await index.search('   '), isEmpty);
      });

      test(
        'plural / prefix folding finds "budgets" and "bud"-style stems',
        () async {
          expect(
            (await index.search('budgets')).map((h) => h.item.externalId),
            contains('e1'),
          );
        },
      );

      test('source and kind filters narrow results', () async {
        final files = await index.search('budget', sources: {'folder'});
        expect(files.map((h) => h.item.externalId), ['f1']);
        final events = await index.search('budget', kinds: {ItemKind.event});
        expect(events.map((h) => h.item.externalId), ['e1']);
      });

      test('limit is honoured', () async {
        expect(await index.search('budget', limit: 2), hasLength(2));
      });

      test(
        'hostile query text is just words, never SQL / FTS syntax',
        () async {
          for (final q in [
            'budget" OR "x',
            "budget'; DROP TABLE items; --",
            'NEAR(budget ravi) AND *',
            r'100% _ \ budget',
          ]) {
            await index.search(q); // must not throw
          }
          expect(await store.countItems('calendar'), 2);
        },
      );

      test('an updated item is found by its new text, not the old', () async {
        await store.upsertItems('calendar', [
          ItemDraft(
            externalId: 'e2',
            kind: ItemKind.event,
            title: 'Orthodontist',
            startsAt: DateTime.utc(2026, 11, 3, 10),
          ),
        ]);
        expect(await index.search('dentist'), isEmpty);
        expect(
          (await index.search('orthodontist')).map((h) => h.item.externalId),
          ['e2'],
        );
      });

      test('revoke wipes search results too', () async {
        await store.wipeConnector('folder');
        final ids = (await index.search(
          'budget',
        )).map((h) => h.item.externalId);
        expect(ids, isNot(contains('f1')));
        expect(await index.search('tadka'), isEmpty);
      });

      test('non-Latin and emoji text is searchable', () async {
        await store.upsertItems('notifications', [
          const ItemDraft(
            externalId: 'n2',
            kind: ItemKind.notification,
            title: 'पार्टी',
            body: 'शनिवार को पार्टी 🎉',
          ),
        ]);
        expect((await index.search('पार्टी')).map((h) => h.item.externalId), [
          'n2',
        ]);
      });
    });
  }

  test(
    'fallback caps its candidate set at $fallbackCandidateCap rows',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final store = ConnectorStore(
        db: db,
        clock: () => DateTime.utc(2026, 11, 1),
      );
      final index = Bm25FallbackSearchIndex(db, store);
      // 2,100 matching rows; the oldest 100 fall outside the candidate window.
      final drafts = [
        for (var i = 0; i < fallbackCandidateCap + 100; i++)
          ItemDraft(
            externalId: 'n$i',
            kind: ItemKind.notification,
            title: 'zebra $i',
          ),
      ];
      await store.upsertItems('notifications', drafts);
      // Make the first 100 the oldest by updated_at.
      await db.customStatement(
        'UPDATE items SET updated_at = 1 WHERE external_id IN '
        "(${[for (var i = 0; i < 100; i++) "'n$i'"].join(',')})",
      );
      final hits = await index.search('zebra', limit: 5000);
      expect(hits, hasLength(fallbackCandidateCap));
      expect(hits.map((h) => h.item.externalId), isNot(contains('n0')));
      await db.close();
    },
  );

  test(
    'FTS5 is rebuilt from existing rows the first time it is enabled',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final store = ConnectorStore(
        db: db,
        clock: () => DateTime.utc(2026, 11, 1),
      );
      // Rows written while the fallback was active (no FTS table yet).
      final fallback = await openSearchIndex(db, store, forceFallback: true);
      await store.upsertItems('folder', [
        const ItemDraft(
          externalId: 'f',
          kind: ItemKind.file,
          title: 'atlas.txt',
          body: 'mountains',
        ),
      ]);
      expect(fallback.engine, 'bm25');
      final fts = await openSearchIndex(db, store);
      expect(fts.engine, 'fts5');
      expect((await fts.search('mountains')).map((h) => h.item.externalId), [
        'f',
      ]);
      await db.close();
    },
  );

  test('falling back after FTS5 was on removes the triggers so writes still '
      'work', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final store = ConnectorStore(
      db: db,
      clock: () => DateTime.utc(2026, 11, 1),
    );
    await openSearchIndex(db, store);
    await openSearchIndex(db, store, forceFallback: true);
    final triggers = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'trigger'")
        .get();
    expect(triggers, isEmpty);
    await store.upsertItems('folder', [
      const ItemDraft(externalId: 'f', kind: ItemKind.file, title: 'x'),
    ]);
    expect(await store.countItems('folder'), 1);
    await db.close();
  });
}
