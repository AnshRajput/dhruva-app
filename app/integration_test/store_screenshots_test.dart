// Drives the real app on a simulator/emulator into the 0.7.0 store-screenshot
// states (the daily assistant): Today, Ask with sources, Meeting prep, Inbox +
// Draft reply (Android only), Library, Privacy. Prints `SHOT <name>` and holds
// the screen; a watcher grabs each frame:
//   iOS:     scripts/capture-store-shots.sh <udid> <model.gguf> <out-dir>
//   Android: flutter test ... -d emulator-5554 | while read l; do
//              [[ $l =~ SHOT\ ([A-Za-z0-9_]+) ]] &&
//                adb exec-out screencap -p > out/${BASH_REMATCH[1]}.png; done
//
// The calendar, contacts, folder and notifications are the fake sources the
// connector tests use, loaded with a believable demo day. The two answers
// (Ask, Draft reply) are written by a real GGUF the test imports:
//   --dart-define=SHOT_MODEL=/abs/path/model.gguf  (adb push it on Android)

import 'dart:async';
import 'dart:convert';

import 'package:dhruva/core/di/connector_providers.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/router/app_router.dart';
import 'package:dhruva/core/router/ask_route.dart';
import 'package:dhruva/core/settings/prefs_store.dart';
import 'package:dhruva/core/settings/what_moved.dart';
import 'package:dhruva/data/connectors/ask_sources.dart';
import 'package:dhruva/data/connectors/connector.dart';
import 'package:dhruva/data/connectors/connector_sources.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/downloads/local_import.dart';
import 'package:dhruva/features/models_hub/state/storage_controller.dart';
import 'package:dhruva/features/onboarding/state/onboarding_controller.dart';
import 'package:dhruva/features/today/state/today_data.dart';
import 'package:dhruva/main.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/fake_connector_sources.dart';
import 'dart_copy_channel.dart';

const _model = String.fromEnvironment('SHOT_MODEL');

const _ravi = Person(name: 'Ravi Menon', email: 'ravi.menon@fieldnote.in');
const _sana = Person(name: 'Sana Iyer', email: 'sana.iyer@fieldnote.in');
const _dev = Person(name: 'Dev Patel', email: 'dev.patel@fieldnote.in');
const _meera = Person(name: 'Meera Shah', email: 'meera.shah@fieldnote.in');

const _budgetNotes =
    'Q4 budget review: notes\n\n'
    'Marketing is up 8 percent on Q3, mostly the Diwali campaign. Hiring is '
    'frozen until January. Vendor spend is Rs 4.2 lakh against a Rs 3.8 lakh '
    'plan, so the revised vendor numbers are the open item. Bring the '
    'signed-off Q3 actuals and the revised vendor quotes to the review.\n';

const _vendorQuotes =
    'Vendor quotes, October\n\n'
    'Printing: Rs 1.1 lakh, 5 day turnaround. Photography: Rs 85,000. '
    'Event hire: Rs 1.6 lakh. Courier and packaging: Rs 45,000. '
    'Total: Rs 4.0 lakh before tax.\n';

const _tripPlan =
    'Jaipur trip, 14 to 16 November\n\n'
    'Flight IndiGo 6E 2134 leaves at 07:10 on the 14th. Stay at the hotel on '
    'MI Road, check-in after 14:00. Dinner with the Sharma family on '
    'Saturday.\n';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('store screenshots', (tester) async {
    expect(_model, isNotEmpty, reason: 'pass --dart-define=SHOT_MODEL=...');
    final android = defaultTargetPlatform == TargetPlatform.android;
    final channel = PathCopyChannel(_model);

    // A fixed morning, so "Up next" and the brief read the same on every run.
    final d = DateTime.now();
    DateTime at(int h, [int m = 0]) => DateTime(d.year, d.month, d.day, h, m);
    final clock = at(7, 42);

    final prefs = MemoryPrefsStore({
      'user_profile': jsonEncode({
        'name': 'Aarav',
        'role': 'runs operations at a small studio',
        'tone': 'Warm',
        'signature': '',
      }),
    });

    // One database shared by the app and the fake connector sources.
    final db = AppDatabase();
    addTearDown(db.close);
    final kit = ConnectorTestKit.create(
      db,
      clock: () => clock,
      notificationsSupported: android,
    );
    addTearDown(kit.dispose);

    final container = ProviderContainer(
      overrides: [
        modelFileChannelProvider.overrideWithValue(channel),
        appDatabaseProvider.overrideWithValue(db),
        connectorHubProvider.overrideWith((ref) async => kit.hub),
        todayClockProvider.overrideWithValue(() => clock),
        prefsStoreProvider.overrideWith((ref) async => prefs),
      ],
    );
    addTearDown(container.dispose);

    await (await container.read(onboardingStoreProvider.future)).markComplete();
    // A real user has closed the one-time "What moved" sheet by now.
    await container.read(whatMovedPendingProvider.notifier).dismiss();
    // Register the GGUF under the catalog's repo id, as a catalog download
    // does, so the app's own label path shows "Qwen2.5-1.5B-Instruct" and not
    // the raw file name. (importLocal would file it under `local/<file>`.)
    await importLocalGguf(
      picked: channel.picked,
      channel: channel,
      modelsDirectory: await container.read(modelsDirectoryProvider.future),
      db: db,
      repoId: 'bartowski/Qwen2.5-1.5B-Instruct-GGUF',
    );
    container.invalidate(storageControllerProvider);
    await container.read(storageControllerProvider.future);

    // ---- the demo day ------------------------------------------------------
    kit.calendar.items = [
      calEvent(
        'e1',
        title: 'Design sync',
        start: at(9, 30),
        attendees: const [_ravi, _sana, _dev],
        location: 'Google Meet',
        description:
            'Walk through the new onboarding screens. Sana brings the '
            'prototype.',
      ),
      calEvent(
        'e2',
        title: 'Budget review',
        start: at(11),
        attendees: const [_ravi, _meera],
        location: 'Room 4B',
        description:
            'Q4 budget review with Ravi and Meera. Bring the revised vendor '
            'numbers and the Q3 actuals.',
      ),
      calEvent(
        'e3',
        title: 'Dentist',
        start: at(16, 30),
        location: 'Smile Clinic, Indiranagar',
      ),
    ];
    for (final p in [_ravi, _sana, _dev, _meera]) {
      kit.contacts.byAddress[p.email!] = DeviceContact(name: p.name!);
    }
    final day0 = at(0);
    kit.folder
      ..nextPick = const FolderGrant(id: 'docs', name: 'Documents')
      ..addFile(
        'Q4 budget notes.txt',
        _budgetNotes,
        modified: day0.subtract(const Duration(days: 2)),
      )
      ..addFile(
        'Vendor quotes October.txt',
        _vendorQuotes,
        modified: day0.subtract(const Duration(days: 5)),
      )
      ..addFile(
        'Jaipur trip plan.txt',
        _tripPlan,
        modified: day0.subtract(const Duration(days: 9)),
      );
    kit.charging.value = true;
    await kit.hub.calendar.connect();
    await kit.hub.contacts.connect();
    await kit.hub.folder.connect();
    if (android) {
      kit.notifications.granted = true;
      await kit.hub.notifications.connect();
      await kit.hub.store.upsertItems(ConnectorIds.notifications, [
        ItemDraft(
          externalId: 'n1',
          kind: ItemKind.notification,
          title: 'Ravi Menon',
          body:
              'Can you send me the revised vendor numbers before the '
              'budget review? Meera wants them on the screen.',
          sentAt: at(7, 12),
          flags: const {'pkg': 'com.whatsapp', 'app': 'WhatsApp'},
        ),
        ItemDraft(
          externalId: 'n2',
          kind: ItemKind.notification,
          title: 'Sana Iyer',
          body:
              'Are you okay to approve the new landing page copy today? '
              'I will publish it after lunch.',
          sentAt: at(6, 48),
          flags: const {'pkg': 'com.slack', 'app': 'Slack'},
        ),
        ItemDraft(
          externalId: 'n3',
          kind: ItemKind.notification,
          title: 'Priya Nair',
          body: 'Dinner on Saturday at 8? Let me know and I will book.',
          sentAt: at(6, 20),
          flags: const {'pkg': 'com.whatsapp', 'app': 'WhatsApp'},
        ),
        ItemDraft(
          externalId: 'n4',
          kind: ItemKind.notification,
          title: 'HDFC Bank',
          body:
              'Rs 12,480 debited from your account ending 4821 at '
              'Reliance Digital.',
          sentAt: at(5, 55),
          flags: const {'pkg': 'com.snapwork.hdfc', 'app': 'HDFC Bank'},
        ),
      ], requireAccount: true);
    }
    await kit.hub.sync.refresh();

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const DhruvaApp()),
    );

    Future<void> shot(String name) async {
      await tester.pump(const Duration(seconds: 2));
      // ignore: avoid_print
      print('SHOT $name');
      await tester.pump(const Duration(seconds: 6));
    }

    Future<List<Message>> assistantRows() => (db.select(
      db.messages,
    )..where((m) => m.role.equalsValue(MessageRole.assistant))).get();

    // Waits until a new assistant reply exists and its text stops changing.
    Future<void> awaitReply(int before) async {
      var last = '';
      var stable = 0;
      for (var i = 0; i < 1200 && stable < 6; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        final rows = await assistantRows();
        if (rows.length <= before) continue;
        final text = rows.last.content;
        // Done = text stopped changing AND the composer's Stop button is gone
        // (a slow emulator can pause mid-answer).
        final streaming = find
            .byKey(const ValueKey('stop'))
            .evaluate()
            .isNotEmpty;
        stable = text.isNotEmpty && text == last && !streaming ? stable + 1 : 0;
        last = text;
      }
    }

    // A simulator/emulator generates far slower than a phone, and the reply
    // footer would print that speed ("0.9 tok/s") and "5m ago". Clear the
    // stored stats so the footer reads "just now": this is data setup in the
    // test, not an app change.
    Future<void> hideSpeedStats() async {
      await (db.update(
        db.messages,
      )..where((m) => m.role.equalsValue(MessageRole.assistant))).write(
        MessagesCompanion(
          tokCount: const Value(null),
          genMs: const Value(null),
          createdAt: Value(DateTime.now()),
        ),
      );
    }

    // Not pumpAndSettle: Today's "in 1h 48m" ticker never settles.
    Future<void> settleFor(Duration t) async {
      for (var i = 0; i < t.inMilliseconds ~/ 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    // 1. Today: brief, Up next, quick actions.
    appRouter.go('/today');
    await settleFor(const Duration(seconds: 4));
    await shot('01_today');

    // 2. Ask with sources: a real answer, chips under it.
    var n = (await assistantRows()).length;
    unawaited(
      appRouter.push(
        askNewLocation(
          q: 'What do I need to bring to the budget review?',
          sources: {AskSource.files},
        ),
      ),
    );
    await settleFor(const Duration(seconds: 3));
    await tester.tap(find.byKey(const ValueKey('send')));
    await awaitReply(n);
    await hideSpeedStats();
    // The open thread holds the old row in memory: reopen it from the DB.
    final threadId = (await assistantRows()).last.conversationId;
    appRouter.go('/today');
    await settleFor(const Duration(seconds: 2));
    unawaited(appRouter.push('/chat/$threadId'));
    await settleFor(const Duration(seconds: 3));
    await shot('02_ask');

    // 3. Prep for a meeting (rule-built from what is on the phone).
    appRouter.go('/today');
    await settleFor(const Duration(seconds: 2));
    final events = await kit.hub.store.itemsOf(
      ConnectorIds.calendar,
      kind: ItemKind.event,
    );
    final budget = events.firstWhere((e) => e.title == 'Budget review');
    unawaited(appRouter.push('/prep/${budget.id}'));
    await settleFor(const Duration(seconds: 3));
    await shot('03_prep');

    // 4. Inbox and Draft reply (Android only: notifications are Android's).
    if (android) {
      appRouter.go('/inbox');
      await settleFor(const Duration(seconds: 3));
      await shot('04_inbox');
      final notes = await kit.hub.store.itemsOf(ConnectorIds.notifications);
      final ravi = notes.firstWhere((i) => i.title == 'Ravi Menon');
      unawaited(appRouter.push('/inbox/item/${ravi.id}'));
      await settleFor(const Duration(seconds: 3));
      await shot('04b_inbox_item');
    }

    // 5. Library, then Privacy (the "nothing leaves your phone" screen).
    appRouter.go('/library');
    await settleFor(const Duration(seconds: 3));
    await shot('05_library');
    unawaited(appRouter.push('/settings/privacy'));
    await settleFor(const Duration(seconds: 3));
    await shot('06_privacy');

    // 6. The drafted reply itself, last: on a slow emulator the model can take
    // minutes, and nothing else should wait on it.
    if (android) {
      appRouter.go('/today');
      await settleFor(const Duration(seconds: 1));
      n = (await assistantRows()).length;
      unawaited(
        appRouter.push(
          Uri(
            path: '/actions',
            queryParameters: {
              'id': 'draft_reply',
              'text':
                  'Ravi Menon: Can you send me the revised vendor numbers '
                  'before the budget review? Meera wants them on the screen.',
              'pkg': 'com.whatsapp',
              'app': 'WhatsApp',
            },
          ).toString(),
        ),
      );
      await settleFor(const Duration(seconds: 3));
      await tester.tap(find.text('Run'));
      await awaitReply(n);
      await settleFor(const Duration(seconds: 3));
      await shot('07_draft_reply');
    }
  }, timeout: const Timeout(Duration(minutes: 30)));
}
