// The guided first-run flow (v2): welcome -> pick a model (download continues
// in the background) -> connect your calendar -> Today. "pick" shows the
// curated catalog ONLY (no raw HF firehose, no quant menu) with the
// device-appropriate model badged "Recommended" and pre-selected; skipping
// anywhere marks onboarding done (shown once) and lands on Today.

import 'package:dhruva/core/device_info/device_info_service.dart';
import 'package:dhruva/core/di/connector_providers.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/core/settings/prefs_store.dart';
import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/core/theme/brand_star.dart';
import 'package:dhruva/data/connectors/connector_sources.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/features/onboarding/state/onboarding_controller.dart';
import 'package:dhruva/features/onboarding/ui/onboarding_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../support/fake_connector_sources.dart';

class _FakeOnboardingStore implements OnboardingStore {
  bool complete = false;
  int completes = 0;
  @override
  Future<bool> isComplete() async => complete;
  @override
  Future<void> markComplete() async {
    completes++;
    complete = true;
  }
}

/// Keeps the flow off the real download pipeline (platform channels) for the
/// welcome/pick/skip paths — the download itself is covered in the state test.
class _StubDownloadController extends OnboardingDownloadController {
  @override
  Future<OnboardingDownloadState> build() async =>
      const OnboardingDownloadState();
}

/// Skips the real pipeline and lands [result] the instant `download` is
/// called, so the flow reaches the next step without platform channels.
class _DownloadResultController extends OnboardingDownloadController {
  _DownloadResultController(this.result);
  final OnboardingDownloadState result;

  @override
  Future<OnboardingDownloadState> build() async =>
      const OnboardingDownloadState();

  @override
  Future<void> download(String repoId, {bool force = false}) async {
    state = AsyncData(result);
  }
}

const _installed = OnboardingDownloadState(
  status: OnboardingDownloadStatus.installed,
  repoId: 'stub/model',
  installedId: 42,
);
const _downloading = OnboardingDownloadState(
  status: OnboardingDownloadStatus.downloading,
  repoId: 'stub/model',
  progress: 0.42,
);
const _failed = OnboardingDownloadState(
  status: OnboardingDownloadStatus.failed,
  repoId: 'stub/model',
  errorMessage: 'Not enough storage space.',
);

const _fakeDeviceInfo = FakeDeviceInfoService(
  memory: DeviceMemoryInfo(totalBytes: 8000000000, availableBytes: 4000000000),
  storage: DeviceStorageInfo(totalBytes: 64000000000, freeBytes: 32000000000),
);

final prefs = MemoryPrefsStore();

class _Pumped {
  _Pumped(this.store, this.kit);
  final _FakeOnboardingStore store;
  final ConnectorTestKit kit;
}

Future<_Pumped> _pumpFlow(
  WidgetTester tester, {
  OnboardingDownloadController Function()? controller,
  bool notificationsSupported = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final kit = ConnectorTestKit.create(
    db,
    notificationsSupported: notificationsSupported,
  );
  addTearDown(kit.dispose);
  final store = _FakeOnboardingStore();
  final router = GoRouter(
    initialLocation: '/onboarding',
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/today',
        builder: (context, state) => const Text('chat-home'),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deviceInfoServiceProvider.overrideWithValue(_fakeDeviceInfo),
        onboardingStoreProvider.overrideWith((ref) async => store),
        prefsStoreProvider.overrideWith((ref) async => prefs),
        appDatabaseProvider.overrideWithValue(db),
        connectorHubProvider.overrideWith((ref) async => kit.hub),
        onboardingDownloadControllerProvider.overrideWith(
          controller ?? _StubDownloadController.new,
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark,
        routerConfig: router,
        builder: (_, child) => Consumer(
          builder: (context, ref, _) {
            // The app-root resume hook main.dart has.
            ref.watch(connectorResumeProvider);
            return child!;
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Pumped(store, kit);
}

Future<_FakeOnboardingStore> _pump(WidgetTester tester) async =>
    (await _pumpFlow(tester)).store;

/// welcome -> pick -> Download (the controller stub lands its result).
Future<void> _toConnect(WidgetTester tester) async {
  await tester.tap(find.text('Get started'));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('Download'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('welcome states what Dhruva is and the value', (tester) async {
    await _pump(tester);
    expect(find.text('Welcome to Dhruva'), findsOneWidget);
    expect(
      find.text('A private AI that runs entirely on your phone.'),
      findsOneWidget,
    );
    expect(find.text('Get started'), findsOneWidget);
  });

  testWidgets('welcome sits balanced: the same space above the mark as below '
      'the last button', (tester) async {
    await _pump(tester);
    await tester.binding.setSurfaceSize(const Size(420, 900));
    await tester.pumpAndSettle();
    final top = tester.getTopLeft(find.byType(DhruvaStar)).dy;
    final bottom = 900 - tester.getBottomLeft(find.text('Skip for now')).dy;
    // The skip button's tap target is taller than its label, so allow a
    // button's worth of slack; a top-hugging layout is hundreds of px off.
    expect((top - bottom).abs(), lessThan(24));
    expect(top, greaterThan(80));
  });

  testWidgets('finishing twice (a second tap while Today slides in) runs '
      'once', (tester) async {
    final store = await _pump(tester);
    await tester.tap(find.text('Skip for now'));
    await tester.pump(); // the first finish is still saving
    await tester.tap(find.text('Skip for now'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(store.completes, 1);
    expect(find.text('chat-home'), findsOneWidget);
  });

  testWidgets('skip on welcome marks onboarding done and lands on Today', (
    tester,
  ) async {
    final store = await _pump(tester);
    expect(store.complete, isFalse);

    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();

    expect(store.complete, isTrue); // shown once
    expect(find.text('chat-home'), findsOneWidget);
    // A new user has nothing that "moved": the upgrade sheet is suppressed.
    expect(prefs.values['what_moved_dismissed'], 'true');
  });

  testWidgets(
    'pick step shows the curated catalog with a single Recommended badge, '
    'no firehose and no quant menu',
    (tester) async {
      await _pump(tester);
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();

      expect(find.text('Pick your first model'), findsOneWidget);
      // Exactly one device-appropriate default is badged.
      expect(find.text('Recommended'), findsOneWidget);
      // No raw HF firehose entry, no quant jargon anywhere in the flow.
      expect(find.textContaining('Hugging Face'), findsNothing);
      expect(find.textContaining('Q4'), findsNothing);
      expect(find.textContaining('quant'), findsNothing);
      // The one obvious next step downloads the selected model in one tap.
      expect(find.textContaining('Download'), findsWidgets);
    },
  );

  group('connect your calendar', () {
    testWidgets('an installed model moves on to "Start with your day"', (
      tester,
    ) async {
      await _pumpFlow(
        tester,
        controller: () => _DownloadResultController(_installed),
      );
      await _toConnect(tester);
      expect(find.text('Start with your day'), findsOneWidget);
      expect(find.text('Allow calendar access'), findsOneWidget);
      expect(find.text('Your model is ready.'), findsOneWidget);
      expect(find.text('Example. Yours will appear on Today.'), findsOneWidget);
    });

    testWidgets('Allow connects the calendar, then Continue lands on Today '
        'and marks onboarding done', (tester) async {
      final p = await _pumpFlow(
        tester,
        controller: () => _DownloadResultController(_installed),
      );
      p.kit.calendar.afterRequest = DevicePermission.granted;
      await _toConnect(tester);
      await tester.tap(find.byKey(const ValueKey('connect-allow')));
      await tester.pumpAndSettle();
      expect(p.kit.calendar.requests, 1);
      expect(
        find.text('Calendar connected. Your day is waiting on Today.'),
        findsOneWidget,
      );
      expect(p.store.complete, isFalse);
      await tester.tap(find.byKey(const ValueKey('connect-continue')));
      await tester.pumpAndSettle();
      expect(p.store.complete, isTrue);
      expect(find.text('chat-home'), findsOneWidget);
    });

    testWidgets('first Deny: retry sentence and Allow stays; second Deny: '
        'Open settings works, Not now still finishes', (tester) async {
      final p = await _pumpFlow(
        tester,
        controller: () => _DownloadResultController(_installed),
      );
      // Android's first Deny: the system will still ask.
      p.kit.calendar.afterRequest = DevicePermission.notDetermined;
      await _toConnect(tester);
      await tester.tap(find.byKey(const ValueKey('connect-allow')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          "Calendar wasn't allowed. Tap Connect to try again",
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('connect-allow')), findsOneWidget);
      expect(find.byKey(const ValueKey('connect-open-settings')), findsNothing);

      // Second Deny: the system will not ask again.
      p.kit.calendar.afterRequest = DevicePermission.denied;
      await tester.tap(find.byKey(const ValueKey('connect-allow')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Calendar access is blocked'), findsOneWidget);
      expect(find.byKey(const ValueKey('connect-allow')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('connect-open-settings')));
      await tester.pumpAndSettle();
      expect(p.kit.calendar.settingsOpened, 1);
      await tester.tap(find.byKey(const ValueKey('connect-not-now')));
      await tester.pumpAndSettle();
      expect(p.store.complete, isTrue);
      expect(find.text('chat-home'), findsOneWidget);
    });

    testWidgets('blocked, then allowed in system settings: coming back moves '
        'on by itself, no second tap', (tester) async {
      final p = await _pumpFlow(
        tester,
        controller: () => _DownloadResultController(_installed),
      );
      p.kit.calendar.afterRequest = DevicePermission.denied;
      await _toConnect(tester);
      await tester.tap(find.byKey(const ValueKey('connect-allow')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Calendar access is blocked'), findsOneWidget);

      // Back from settings, still off: the fix stays on screen.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('connect-calendar-denied')),
        findsOneWidget,
      );
      expect(p.store.complete, isFalse);

      // Allowed in settings, back to the app.
      p.kit.calendar.perm = DevicePermission.granted;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(p.store.complete, isTrue);
      expect(find.text('chat-home'), findsOneWidget);
    });

    testWidgets('Skip is always there', (tester) async {
      final p = await _pumpFlow(
        tester,
        controller: () => _DownloadResultController(_installed),
      );
      await _toConnect(tester);
      await tester.tap(find.byKey(const ValueKey('connect-skip')));
      await tester.pumpAndSettle();
      expect(p.store.complete, isTrue);
      expect(find.text('chat-home'), findsOneWidget);
    });

    testWidgets('the download carries on: "Continue while it downloads" shows '
        'progress on the connect step', (tester) async {
      await _pumpFlow(
        tester,
        controller: () => _DownloadResultController(_downloading),
      );
      await _toConnect(tester);
      expect(find.text('Continue while it downloads'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('onboarding-continue')));
      await tester.pumpAndSettle();
      expect(find.text('Start with your day'), findsOneWidget);
      expect(
        find.text('Your model is downloading in the background · 42%'),
        findsOneWidget,
      );
    });

    testWidgets('download errors keep their recovery on the download step', (
      tester,
    ) async {
      await _pumpFlow(
        tester,
        controller: () => _DownloadResultController(_failed),
      );
      await _toConnect(tester);
      expect(find.text("Download didn't finish"), findsOneWidget);
      expect(find.text('Not enough storage space.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Pick another model'), findsOneWidget);
    });

    testWidgets('extras: Folder and (Android) Notifications can be added', (
      tester,
    ) async {
      final p = await _pumpFlow(
        tester,
        controller: () => _DownloadResultController(_installed),
      );
      p.kit.folder.nextPick = const FolderGrant(id: 'g', name: 'Notes');
      await _toConnect(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('connect-extra-folder')),
      );
      expect(
        find.byKey(const ValueKey('connect-extra-notifications')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('connect-extra-folder')));
      await tester.pumpAndSettle();
      expect(find.text('Added'), findsOneWidget);
    });

    testWidgets('iOS: no notifications row', (tester) async {
      await _pumpFlow(
        tester,
        notificationsSupported: false,
        controller: () => _DownloadResultController(_installed),
      );
      await _toConnect(tester);
      expect(
        find.byKey(const ValueKey('connect-extra-notifications')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('connect-extra-folder')),
        findsOneWidget,
      );
    });
  });

  testWidgets('skip on the pick step also marks onboarding done', (
    tester,
  ) async {
    final store = await _pump(tester);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();

    expect(store.complete, isTrue);
    expect(find.text('chat-home'), findsOneWidget);
  });
}
