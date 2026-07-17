// QA (Loop-4 attack list #8): navigation — deep links, back behavior, and
// state preservation across bottom-nav tab switches, driven through the
// real `appRouter` singleton + `DhruvaApp` (same harness shape as
// app_shell_test.dart).

import 'dart:async' show unawaited;

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/router/app_router.dart';
import 'package:dhruva/data/chat/chat_repository.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/hf_api/hf_api_client.dart';
import 'package:dhruva/main.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _fakeDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

void main() {
  late AppDatabase db;
  late ChatRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ChatRepository(db: db);
    // appRouter is a top-level singleton shared across the whole test
    // process (imported, not constructed per-test) — reset its location
    // before every test so navigation state never leaks between tests.
    appRouter.go('/chat');
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
          hfApiClientProvider.overrideWithValue(
            HfApiClient(
              client: MockClient((request) async => http.Response('[]', 200)),
            ),
          ),
        ],
        child: const DhruvaApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'deep link to a nonexistent (but numeric) conversation id is graceful: '
    'no exception, renders an empty/no-model state instead of crashing',
    (tester) async {
      await pumpApp(tester);
      appRouter.go('/chat/999999');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // ChatController.build() returns a bare ChatThreadState() for a
      // missing conversation id (getConversation -> null) — modelId is
      // null too, so the thread screen falls back to the "no model
      // installed" empty state rather than showing garbage or throwing.
      expect(find.text('No model installed yet'), findsOneWidget);
    },
  );

  testWidgets(
    'BUG repro: a malformed (non-numeric, not "new") /chat/:id deep link '
    'throws uncaught inside the route builder (int.parse) instead of '
    'failing gracefully',
    (tester) async {
      await pumpApp(tester);
      appRouter.go('/chat/not-a-number');
      await tester.pumpAndSettle();

      // app_router.dart's GoRoute builder does `int.parse(idParam)`
      // unguarded for anything that isn't literally "new" — a malformed id
      // (e.g. from an external share intent or a stale/hand-typed link)
      // throws a FormatException synchronously during route build.
      expect(tester.takeException(), isA<FormatException>());
    },
  );

  testWidgets('/settings/about is reachable as a direct deep link', (
    tester,
  ) async {
    await pumpApp(tester);
    appRouter.go('/settings/about');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Dhruva AI'), findsOneWidget);
    expect(find.textContaining('Zero telemetry'), findsOneWidget);
  });

  testWidgets('back navigation from a pushed About page returns to /chat', (
    tester,
  ) async {
    await pumpApp(tester);
    // Confirms we're starting on the Chat tab/home.
    expect(find.text('Chats'), findsOneWidget);

    unawaited(appRouter.push('/settings/about'));
    await tester.pumpAndSettle();
    expect(find.text('Dhruva AI'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('Chats'), findsOneWidget);
    expect(find.text('Dhruva AI'), findsNothing);
  });

  testWidgets(
    'chat list scroll position survives a visit to the Models tab and back',
    (tester) async {
      final baseTime = DateTime.utc(2026, 1, 1);
      for (var i = 0; i < 30; i++) {
        final id = await repo.createConversation(title: 'Chat $i');
        // Deterministic ordering (most-recently-updated first): higher i ->
        // later updatedAt -> appears nearer the top of the list.
        await (db.update(
          db.conversations,
        )..where((t) => t.id.equals(id))).write(
          ConversationsCompanion(
            updatedAt: Value(baseTime.add(Duration(seconds: i))),
          ),
        );
      }

      await pumpApp(tester);
      expect(find.text('Chat 29'), findsOneWidget); // most-recent, at top

      // Scroll the conversation list (the vertical ListView — the folder
      // chip row is the other, horizontal, ListView on this screen).
      final verticalList = find.byWidgetPredicate(
        (w) => w is ListView && w.scrollDirection == Axis.vertical,
      );
      await tester.drag(verticalList, const Offset(0, -2000));
      await tester.pumpAndSettle();

      final scrollable = find.descendant(
        of: verticalList,
        matching: find.byType(Scrollable),
      );
      final offsetAfterScroll = tester
          .state<ScrollableState>(scrollable)
          .position
          .pixels;
      expect(offsetAfterScroll, greaterThan(0));

      // Visit the Models tab...
      await tester.tap(find.text('Models'));
      await tester.pumpAndSettle();
      expect(find.text('Chats'), findsNothing);

      // ...and back to Chat.
      await tester.tap(find.text('Chat'));
      await tester.pumpAndSettle();

      final verticalListAfter = find.byWidgetPredicate(
        (w) => w is ListView && w.scrollDirection == Axis.vertical,
      );
      final scrollableAfter = find.descendant(
        of: verticalListAfter,
        matching: find.byType(Scrollable),
      );
      final offsetAfterTabSwitch = tester
          .state<ScrollableState>(scrollableAfter)
          .position
          .pixels;
      expect(
        offsetAfterTabSwitch,
        offsetAfterScroll,
        reason:
            'StatefulShellRoute.indexedStack keeps each branch\'s Navigator '
            '(and widget state) alive offstage rather than disposing it, so '
            'the scroll position should be exactly preserved across a tab '
            'round trip.',
      );
    },
  );
}
