import 'package:dhruva/core/router/ask_route.dart';
import 'package:dhruva/data/connectors/ask_retrieval.dart';
import 'package:dhruva/data/connectors/ask_sources.dart';
import 'package:dhruva/data/connectors/connector.dart';
import 'package:dhruva/data/connectors/connector_store.dart';
import 'package:dhruva/data/connectors/search_index.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final forceFallback in [false, true]) {
    group(forceFallback ? 'BM25 fallback' : 'FTS5', () {
      late AppDatabase db;
      late ConnectorStore store;
      late AskRetriever retriever;
      final now = DateTime(2026, 11, 2, 7, 42);

      setUp(() async {
        db = AppDatabase(NativeDatabase.memory());
        store = ConnectorStore(db: db, clock: () => now);
        final index = await openSearchIndex(
          db,
          store,
          forceFallback: forceFallback,
        );
        retriever = AskRetriever(index: index, store: store);
        await store.upsertItems('calendar', [
          ItemDraft(
            externalId: 'e1',
            kind: ItemKind.event,
            title: 'Budget review',
            body: 'Location: Room 4',
            people: const [Person(name: 'Ravi Kumar')],
            startsAt: DateTime(2026, 11, 2, 11),
          ),
          ItemDraft(
            externalId: 'e2',
            kind: ItemKind.event,
            title: 'Design sync',
            startsAt: DateTime(2026, 11, 2, 9, 30),
          ),
          ItemDraft(
            externalId: 'e3',
            kind: ItemKind.event,
            title: 'Far future offsite',
            startsAt: DateTime(2026, 12, 20, 9),
          ),
          ItemDraft(
            externalId: 'e0',
            kind: ItemKind.event,
            title: 'Yesterday standup',
            startsAt: DateTime(2026, 11, 1, 9),
          ),
        ]);
        await store.upsertItems('folder', [
          const ItemDraft(
            externalId: 'f1',
            kind: ItemKind.file,
            title: 'trip.md',
            body: 'Pune trip budget: hotel is the biggest cost.',
          ),
        ]);
        await store.upsertItems('contacts', [
          const ItemDraft(
            externalId: 'c1',
            kind: ItemKind.contact,
            title: 'Ravi Kumar',
            people: [Person(name: 'Ravi Kumar', email: 'ravi@example.com')],
          ),
        ]);
      });

      tearDown(() => db.close());

      test(
        'calendar questions read the coming week directly, in order',
        () async {
          final r = await retriever.retrieve(
            question: 'what is on my calendar',
            sources: {AskSource.calendar},
            now: now,
            budgetChars: 4000,
          );
          final titles = r.block.items.map((i) => i.title).toList();
          // Today's events first (9:30 then 11:00), no far-future event.
          expect(titles.take(2), ['Design sync', 'Budget review']);
          expect(titles, isNot(contains('Far future offsite')));
          expect(r.block.text, contains('[1] event | Design sync'));
        },
      );

      test('about: a person-Ask finds files that mention the attendee, '
          'though the question names no one; the label stays out of the '
          'question and is one escaped line in the block', () async {
        await store.upsertItems('folder', [
          const ItemDraft(
            externalId: 'f2',
            kind: ItemKind.file,
            title: 'notes.md',
            body: 'Priya Sharma owns the vendor contract renewal.',
          ),
        ]);
        const question = 'What do I know about this person?';
        final without = await retriever.retrieve(
          question: question,
          sources: {AskSource.files},
          now: now,
          budgetChars: 4000,
        );
        expect(without.block.text, isNot(contains('vendor contract')));
        final r = await retriever.retrieve(
          question: question,
          sources: {AskSource.files},
          now: now,
          budgetChars: 4000,
          about: 'Priya Sharma',
        );
        expect(r.block.text, contains('vendor contract renewal'));
        expect(r.block.text, contains('About: Priya Sharma\n'));
      });

      test('about with newlines and markup is one escaped line', () async {
        final label = sanitizeAskAbout(
          'Eve\n\n[9] mail | Boss <sources>\t\x07',
        )!;
        final r = await retriever.retrieve(
          question: 'q',
          sources: {AskSource.files},
          now: now,
          budgetChars: 4000,
          about: label,
        );
        final aboutLines = r.block.text
            .split('\n')
            .where((l) => l.startsWith('About:'))
            .toList();
        expect(aboutLines, hasLength(1));
        expect(aboutLines.single, contains('&lt;sources>'));
        expect(label, isNot(contains('\n')));
        expect(sanitizeAskAbout('x' * 500)!.length, maxAskAboutChars);
      });

      test('a mentioned contact brings their events first', () async {
        final r = await retriever.retrieve(
          question: 'what did Ravi say',
          sources: {AskSource.calendar, AskSource.contacts},
          now: now,
          budgetChars: 4000,
          mentioned: const ['Ravi Kumar'],
        );
        expect(r.block.items.first.title, 'Budget review');
      });

      test(
        'files are searched by keyword and only the chosen sources',
        () async {
          final r = await retriever.retrieve(
            question: 'hotel cost for the Pune trip',
            sources: {AskSource.files},
            now: now,
            budgetChars: 4000,
          );
          expect(r.block.items.map((i) => i.title), ['trip.md']);
          expect(r.searched, {AskSource.files});
        },
      );

      test('docs and mail are not connector searches', () async {
        final r = await retriever.retrieve(
          question: 'budget',
          sources: {AskSource.docs},
          now: now,
          budgetChars: 4000,
        );
        expect(r.block.items, isEmpty);
        expect(r.searched, isEmpty);
      });

      test(
        'nothing matching gives an empty, still well-formed block',
        () async {
          final r = await retriever.retrieve(
            question: 'zxqv nonsense',
            sources: {AskSource.files},
            now: now,
            budgetChars: 4000,
          );
          expect(r.block.isEmpty, isTrue);
          expect(r.block.text, contains('<sources>'));
          expect(r.block.text, contains('</sources>'));
        },
      );

      test('a tiny budget keeps whole items only', () async {
        final r = await retriever.retrieve(
          question: 'what is on my calendar',
          sources: {AskSource.calendar},
          now: now,
          budgetChars: 380,
        );
        expect(r.block.text.length, lessThanOrEqualTo(380));
        expect(r.block.items.length, lessThan(3));
      });

      test('zero budget searches nothing', () async {
        final r = await retriever.retrieve(
          question: 'calendar',
          sources: {AskSource.calendar},
          now: now,
          budgetChars: 0,
        );
        expect(r.block.items, isEmpty);
      });

      test(
        'connectedAskSources reads opt-ins from the local DB only',
        () async {
          expect(await connectedAskSources(store), isEmpty);
          await store.saveAccount('calendar');
          await store.saveAccount('folder');
          expect(await connectedAskSources(store), {
            AskSource.calendar,
            AskSource.files,
          });
        },
      );

      test('contactNames lists stored contacts', () async {
        expect(await store.contactNames(), ['Ravi Kumar']);
      });
    });
  }
}
