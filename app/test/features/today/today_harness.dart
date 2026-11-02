// Harness for the Today widget tests: the REAL connector hub, store and
// providers over an in-memory database, with only the OS edges faked (the
// calendar/contacts/folder/notification sources, the on-device model, the
// clock, prefs, the OS calendar intent).

import 'package:dhruva/core/device_health/device_health.dart';
import 'package:dhruva/core/device_health/device_health_provider.dart';
import 'package:dhruva/core/di/connector_providers.dart';
import 'package:dhruva/core/di/model_download.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/settings/prefs_store.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/connectors/connector.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/data/downloads/download_manager.dart';
import 'package:dhruva/features/today/state/brief_writer.dart';
import 'package:dhruva/features/today/state/today_data.dart';
import 'package:dhruva/features/today/ui/day_timeline_screen.dart';
import 'package:dhruva/features/today/ui/today_actions.dart';
import 'package:dhruva/features/today/ui/today_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/device_health_fakes.dart';
import '../../support/fake_connector_sources.dart';
import 'today_fixtures.dart';

class FakeBriefWriter implements BriefWriter {
  FakeBriefWriter({
    this.model = BriefModelStatus.ready,
    this.output = 'Design sync is at 9:30 [1]. Ravi Menon messaged you [3].',
  });

  BriefModelStatus model;
  String output;
  Object? failWith;
  int prepares = 0;
  final prompts = <String>[];

  @override
  Future<BriefModelStatus> status() async => model;

  @override
  Future<void> prepare() async {
    prepares++;
    model = BriefModelStatus.ready;
  }

  @override
  Future<String> write({required String system, required String prompt}) async {
    prompts.add(prompt);
    final f = failWith;
    if (f != null) throw f;
    return output;
  }
}

class TodayHarness {
  TodayHarness(this.db, this.kit, this.writer, this.prefs);
  final AppDatabase db;
  final ConnectorTestKit kit;
  final FakeBriefWriter writer;
  final MemoryPrefsStore prefs;

  /// Every full-screen route the UI pushed, as written.
  final visited = <String>[];
  final openedCalendarAt = <DateTime>[];

  /// Connects the calendar with the comps' two meetings.
  Future<void> seedCalendar() async {
    kit.calendar.items = [
      calEvent(
        'e1',
        title: 'Design sync',
        start: at(9, 30),
        attendees: const [
          Person(name: 'Ravi', email: 'ravi@x.test'),
          Person(name: 'Sana', email: 'sana@x.test'),
          Person(name: 'Dev', email: 'dev@x.test'),
        ],
        location: 'https://meet.google.com/abc',
      ),
      calEvent(
        'e2',
        title: 'Budget review',
        start: at(11),
        location: 'Room 4B',
      ),
    ];
    await kit.hub.calendar.connect();
    await kit.hub.sync.refresh();
  }

  /// Connects notifications and stores [items] (already shaped by the
  /// fixtures).
  Future<void> seedNotifications(List<ConnectorItem> items) async {
    kit.notifications.granted = true;
    await kit.hub.notifications.connect();
    await kit.hub.store.upsertItems(ConnectorIds.notifications, [
      for (final i in items)
        ItemDraft(
          externalId: i.externalId,
          kind: ItemKind.notification,
          title: i.title,
          body: i.body,
          sentAt: i.sentAt,
          flags: i.flags,
        ),
    ], requireAccount: true);
  }
}

/// The app-root resume hook main.dart has (grants made in system settings).
Widget withAppRootResume(Widget? child) => Consumer(
  builder: (context, ref, _) {
    ref.watch(connectorResumeProvider);
    return child!;
  },
);

/// Builds the app around Today. [home] defaults to Today; pass
/// `const DayTimelineScreen()` for the timeline.
Future<TodayHarness> pumpToday(
  WidgetTester tester, {
  FakeBriefWriter? writer,
  MemoryPrefsStore? prefs,
  bool notificationsSupported = true,
  Future<void> Function(TodayHarness h)? seed,
  Widget? home,
  List<Override> overrides = const [],
  DeviceHealth? health,

  /// A model download running right now (null: none).
  DownloadProgress? download,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final kit = ConnectorTestKit.create(
    db,
    clock: () => fixtureNow,
    notificationsSupported: notificationsSupported,
  );
  addTearDown(kit.dispose);
  final h = TodayHarness(
    db,
    kit,
    writer ?? FakeBriefWriter(),
    prefs ?? MemoryPrefsStore(),
  );
  if (seed != null) await seed(h);

  GoRoute stub(String path) => GoRoute(
    path: path,
    builder: (context, state) {
      h.visited.add(state.uri.toString());
      return Scaffold(
        appBar: AppBar(title: Text('route:$path')),
        body: const SizedBox(),
      );
    },
  );
  final router = GoRouter(
    initialLocation: '/today',
    routes: [
      GoRoute(
        path: '/today',
        builder: (context, state) => home ?? const TodayScreen(),
      ),
      GoRoute(path: '/day', builder: (_, _) => const DayTimelineScreen()),
      stub('/ask/new'),
      stub('/actions'),
      stub('/settings'),
      stub('/settings/connectors'),
      stub('/settings/models'),
      stub('/inbox/connect'),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        connectorHubProvider.overrideWith((ref) async => kit.hub),
        todayClockProvider.overrideWithValue(() => fixtureNow),
        // No 30 s periodic timer in tests (a pending timer fails the test).
        minuteTickProvider.overrideWith((ref) => Stream.value(fixtureNow)),
        prefsStoreProvider.overrideWith((ref) async => h.prefs),
        briefWriterProvider.overrideWithValue(h.writer),
        // No real download manager (plugins) in widget tests.
        modelDownloadProvider.overrideWith((ref) => Stream.value(download)),
        openCalendarProvider.overrideWithValue((t) async {
          h.openedCalendarAt.add(t);
          return true;
        }),
        deviceHealthServiceProvider.overrideWithValue(
          FakeHealthService(health ?? DeviceHealth.unknown),
        ),
        deviceGuardStoreProvider.overrideWith(
          (ref) async => MemoryGuardStore(),
        ),
        ...overrides,
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark,
        routerConfig: router,
        builder: (_, child) => withAppRootResume(child),
      ),
    ),
  );
  await settle(tester);
  return h;
}

/// Lets streams, futures and post-frame work run. Not `pumpAndSettle`: the
/// "in 1h 48m" ticker is a periodic timer and never settles.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// `testWidgets` that unmounts the app and lets drift's zero-length stream
/// timers fire before the test ends (a pending timer fails the test).
void todayTest(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    await body(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
