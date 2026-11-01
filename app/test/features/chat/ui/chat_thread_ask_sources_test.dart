import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/ask_providers.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/connectors/ask_sources.dart';
import 'package:dhruva/data/connectors/connector.dart';
import 'package:dhruva/data/connectors/connector_store.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/engine_bindings/engine_service.dart';
import 'package:dhruva/engine_bindings/fake_engine_service.dart';
import 'package:dhruva/features/chat/state/chat_controller.dart';
import 'package:dhruva/features/chat/ui/chat_thread_screen.dart';
import 'package:dhruva/voice/fake_audio_sink.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../support/device_health_fakes.dart';

const _fakeDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

void main() {
  late AppDatabase db;
  late FakeEngineService engine;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    engine = FakeEngineService(
      scriptedTokens: const ['You meet at nine ', '[1].'],
      tokenDelay: const Duration(milliseconds: 5),
    );
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await db.close();
  });

  Future<int> insertModel() => db
      .into(db.installedModels)
      .insert(
        InstalledModelsCompanion.insert(
          repoId: 'bartowski/Llama-3.2-1B-Instruct-GGUF',
          fileName: 'model.gguf',
          sizeBytes: 100,
          localPath: '/tmp/dhruva-ask-test.gguf',
          downloadedAt: DateTime.utc(2026, 7, 17),
        ),
      );

  Future<void> pump(
    WidgetTester tester,
    ChatRouteArgs args, {
    Map<String, bool> connectors = const {
      ConnectorIds.calendar: true,
      ConnectorIds.contacts: false,
      ConnectorIds.folder: false,
    },
    List<String> routed = const [],
  }) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => ChatThreadScreen(args: args),
        ),
        GoRoute(
          path: '/settings/connectors',
          builder: (context, state) {
            routed.add(state.uri.toString());
            return const Scaffold(body: Text('connectors-screen'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
          engineServiceProvider.overrideWithValue(engine),
          audioSinkProvider.overrideWithValue(FakeAudioSink()),
          askConnectorsProvider.overrideWithValue(connectors),
          ...deviceHealthTestOverrides(),
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Mail is hidden; unconnected sources offer Connect', (
    tester,
  ) async {
    final modelId = await insertModel();
    await pump(tester, ChatRouteArgs(initialModelId: modelId));
    expect(find.text('Search in'), findsOneWidget);
    expect(find.byKey(const ValueKey('search-in-auto')), findsOneWidget);
    expect(find.byKey(const ValueKey('search-in-calendar')), findsOneWidget);
    expect(find.byKey(const ValueKey('search-in-mail')), findsNothing);
    // Contacts and Files are not connected: each says Connect.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('search-in-contacts')),
        matching: find.text('Connect'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('search-in-calendar')),
        matching: find.text('Connect'),
      ),
      findsNothing,
    );
  });

  testWidgets('tapping Connect opens that connector card, not a dead tap', (
    tester,
  ) async {
    final modelId = await insertModel();
    final routed = <String>[];
    await pump(tester, ChatRouteArgs(initialModelId: modelId), routed: routed);
    await tester.tap(find.byKey(const ValueKey('search-in-contacts')));
    await tester.pumpAndSettle();
    expect(find.text('connectors-screen'), findsOneWidget);
    expect(routed.single, '/settings/connectors?connector=contacts');
  });

  testWidgets('Auto previews its pick while typing; a tap pins instead', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final modelId = await insertModel();
    await pump(tester, ChatRouteArgs(initialModelId: modelId));
    expect(find.bySemanticsLabel('Calendar, not searched'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      'What meetings do I have tomorrow?',
    );
    await tester.pump();
    expect(find.bySemanticsLabel('Calendar, searched'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Auto, on')), findsOneWidget);

    // Tapping the chip leaves Auto and pins the set.
    await tester.tap(find.byKey(const ValueKey('search-in-calendar')));
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp(r'^Auto, off')), findsOneWidget);
    expect(find.bySemanticsLabel('Calendar, not searched'), findsOneWidget);

    // And Auto brings the rules back.
    await tester.tap(find.byKey(const ValueKey('search-in-auto')));
    await tester.pump();
    expect(find.bySemanticsLabel('Calendar, searched'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a prefilled route arrives with text and sources pinned', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final modelId = await insertModel();
    await pump(
      tester,
      ChatRouteArgs(
        initialModelId: modelId,
        initialDraft: 'Prep me for Budget review',
        initialSources: const {AskSource.calendar, AskSource.contacts},
      ),
      connectors: const {
        ConnectorIds.calendar: true,
        ConnectorIds.contacts: true,
        ConnectorIds.folder: true,
      },
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'Prep me for Budget review');
    // Not sent: no message yet.
    expect(engine.generateCount, 0);
    expect(find.bySemanticsLabel(RegExp(r'^Auto, off')), findsOneWidget);
    expect(find.bySemanticsLabel('Calendar, searched'), findsOneWidget);
    expect(find.bySemanticsLabel('Contacts, searched'), findsOneWidget);
    expect(find.bySemanticsLabel('Files, not searched'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('Ask about a file: Files pinned, the file shown as an About '
      'chip, Auto off', (tester) async {
    final handle = tester.ensureSemantics();
    final modelId = await insertModel();
    final store = ConnectorStore(db: db);
    await store.saveAccount('folder');
    await store.upsertItems('folder', [
      const ItemDraft(
        externalId: 'doc:budget.md',
        kind: ItemKind.file,
        title: 'budget.md',
        body: 'The Q4 budget needs approval.',
        flags: {'fileId': 'doc:budget.md'},
      ),
    ]);
    final id = (await db.select(db.items).get()).single.id;
    await pump(
      tester,
      ChatRouteArgs(
        initialModelId: modelId,
        initialSources: const {AskSource.files},
        focusItemIds: [id],
      ),
      connectors: const {
        ConnectorIds.calendar: true,
        ConnectorIds.contacts: true,
        ConnectorIds.folder: true,
      },
    );
    expect(find.byKey(const ValueKey('search-in-focus-0')), findsOneWidget);
    expect(find.text('budget.md'), findsOneWidget);
    expect(
      find.bySemanticsLabel('About budget.md. Always searched.'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp(r'^Auto, off')), findsOneWidget);
    expect(find.bySemanticsLabel('Files, searched'), findsOneWidget);
    expect(find.bySemanticsLabel('Calendar, not searched'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a grounded answer shows source chips that open the item', (
    tester,
  ) async {
    final modelId = await insertModel();
    final store = ConnectorStore(db: db);
    await store.saveAccount('calendar');
    final start = DateTime.now().add(const Duration(minutes: 30));
    await store.upsertItems('calendar', [
      ItemDraft(
        externalId: 'e1',
        kind: ItemKind.event,
        title: 'Design sync',
        body: 'Location: Room 4',
        people: const [Person(name: 'Ravi Kumar')],
        startsAt: start,
        flags: {
          'end': start.add(const Duration(hours: 1)).millisecondsSinceEpoch,
        },
      ),
    ]);
    await pump(tester, ChatRouteArgs(initialModelId: modelId));

    await tester.enterText(find.byType(TextField), 'What meetings do I have?');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();

    // The model saw the events inside the delimited block...
    final userTurn = engine.lastMessages!.lastWhere(
      (t) => t.role == EngineRole.user,
    );
    expect(userTurn.content, contains('<sources>'));
    expect(userTurn.content, contains('Design sync'));
    expect(userTurn.content, contains('Question: What meetings do I have?'));

    // ...and the answer carries a chip for the item it cited.
    final label = '${shortDate(start)}, Design sync';
    expect(find.text('Sources'), findsOneWidget);
    expect(find.text(label), findsOneWidget);

    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('source-sheet')), findsOneWidget);
    expect(find.text('Design sync'), findsWidgets);
    expect(find.text('With Ravi Kumar'), findsOneWidget);
    expect(find.text('Location: Room 4'), findsOneWidget);
  });

  testWidgets('an ungrounded answer gets no source chips', (tester) async {
    final modelId = await insertModel();
    await pump(tester, ChatRouteArgs(initialModelId: modelId));
    await tester.enterText(find.byType(TextField), 'Write a haiku about rain');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();
    final userTurn = engine.lastMessages!.lastWhere(
      (t) => t.role == EngineRole.user,
    );
    expect(userTurn.content, 'Write a haiku about rain');
    expect(find.byKey(const ValueKey('answer-sources')), findsNothing);
  });

  testWidgets('a cited item that is gone opens a plain notice', (tester) async {
    final modelId = await insertModel();
    final store = ConnectorStore(db: db);
    await store.saveAccount('calendar');
    await store.upsertItems('calendar', [
      ItemDraft(
        externalId: 'e1',
        kind: ItemKind.event,
        title: 'Design sync',
        startsAt: DateTime.now().add(const Duration(minutes: 30)),
      ),
    ]);
    await pump(tester, ChatRouteArgs(initialModelId: modelId));
    await tester.enterText(find.byType(TextField), 'What meetings do I have?');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();

    // The user disconnects Calendar: its items are wiped.
    await store.wipeConnector('calendar');
    await tester.tap(find.textContaining('Design sync'));
    await tester.pumpAndSettle();
    expect(find.text('No longer on this phone'), findsOneWidget);
  });
}
