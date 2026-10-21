import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/core/update/shorebird_update_banner.dart';
import 'package:dhruva/core/update/shorebird_update_service.dart';
import 'package:dhruva/features/settings/app_info.dart';
import 'package:dhruva/features/settings/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

class FakeUpdater implements ShorebirdUpdater {
  FakeUpdater({this.available = true, this.status = UpdateStatus.outdated});
  bool available;
  UpdateStatus status;
  int checks = 0;
  int updates = 0;
  bool failNext = false;
  bool failCheck = false;

  @override
  bool get isAvailable => available;
  @override
  Future<Patch?> readCurrentPatch() async => const Patch(number: 3);
  @override
  Future<Patch?> readNextPatch() async => null;
  @override
  Future<UpdateStatus> checkForUpdate({UpdateTrack? track}) async {
    checks++;
    if (failCheck) throw Exception('offline');
    return status;
  }

  @override
  Future<void> update({UpdateTrack? track}) async {
    updates++;
    if (failNext) {
      failNext = false;
      throw const UpdateException(
        message: 'x',
        reason: UpdateFailureReason.downloadFailed,
      );
    }
  }
}

({
  ProviderContainer c,
  FakeUpdater u,
  List<DateTime> clock,
  int Function() restarts,
})
make({FakeUpdater? u, bool restartOk = true}) {
  final up = u ?? FakeUpdater();
  final clock = [DateTime(2026, 1, 1, 9)];
  var restarts = 0;
  final c = ProviderContainer(
    overrides: [
      shorebirdUpdaterProvider.overrideWithValue(up),
      shorebirdNowProvider.overrideWithValue(() => clock.first),
      shorebirdRestartProvider.overrideWithValue(() async {
        restarts++;
        return restartOk;
      }),
    ],
  );
  addTearDown(c.dispose);
  return (c: c, u: up, clock: clock, restarts: () => restarts);
}

const _ms = Duration(milliseconds: 300);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('service', () {
    test('available -> download -> readyToRestart -> restart', () async {
      final t = make();
      t.c.read(shorebirdUpdateProvider);
      await Future<void>.delayed(Duration.zero);
      final n = t.c.read(shorebirdUpdateProvider.notifier);
      expect(t.c.read(shorebirdUpdateProvider).phase, ShorebirdPhase.available);
      expect(t.c.read(shorebirdUpdateProvider).patch, 3);
      expect(t.u.updates, 0, reason: 'never downloads without a tap');

      await n.download();
      expect(
        t.c.read(shorebirdUpdateProvider).phase,
        ShorebirdPhase.readyToRestart,
      );
      expect(t.restarts(), 0, reason: 'never auto-restarts');
      await n.restart();
      expect(t.restarts(), 1);
    });

    test('failure -> retry succeeds', () async {
      final t = make(u: FakeUpdater()..failNext = true);
      t.c.read(shorebirdUpdateProvider);
      await Future<void>.delayed(Duration.zero);
      final n = t.c.read(shorebirdUpdateProvider.notifier);
      await n.download();
      expect(t.c.read(shorebirdUpdateProvider).phase, ShorebirdPhase.failed);
      await n.download();
      expect(
        t.c.read(shorebirdUpdateProvider).phase,
        ShorebirdPhase.readyToRestart,
      );
      expect(t.u.updates, 2);
    });

    test('not a Shorebird build -> unavailable, nothing checked', () async {
      final t = make(u: FakeUpdater(available: false));
      t.c.read(shorebirdUpdateProvider);
      await Future<void>.delayed(Duration.zero);
      final s = t.c.read(shorebirdUpdateProvider);
      expect(s.phase, ShorebirdPhase.unavailable);
      expect(s.hasNudge, isFalse);
      expect(t.u.checks, 0);
    });

    test('check is throttled to 30 min unless forced', () async {
      final t = make(u: FakeUpdater(status: UpdateStatus.upToDate));
      t.c.read(shorebirdUpdateProvider);
      await Future<void>.delayed(Duration.zero);
      final n = t.c.read(shorebirdUpdateProvider.notifier);
      await n.check();
      expect(t.u.checks, 1);
      t.clock[0] = t.clock.first.add(const Duration(minutes: 29));
      await n.check();
      expect(t.u.checks, 1);
      await n.check(force: true);
      expect(t.u.checks, 2);
      t.clock[0] = t.clock.first.add(const Duration(minutes: 31));
      await n.check();
      expect(t.u.checks, 3);
    });

    test('failed check reports false', () async {
      final t = make(u: FakeUpdater(status: UpdateStatus.upToDate));
      t.c.read(shorebirdUpdateProvider);
      await Future<void>.delayed(Duration.zero);
      final n = t.c.read(shorebirdUpdateProvider.notifier);
      expect(await n.check(force: true), isTrue);
      t.u.failCheck = true;
      expect(await n.check(force: true), isFalse);
      expect(t.c.read(shorebirdUpdateProvider).phase, ShorebirdPhase.idle);
    });

    test('Later snoozes for 6 h', () async {
      final t = make();
      t.c.read(shorebirdUpdateProvider);
      await Future<void>.delayed(Duration.zero);
      t.c.read(shorebirdUpdateProvider.notifier).snooze();
      final s = t.c.read(shorebirdUpdateProvider);
      final start = t.clock.first;
      expect(
        s.snoozed(start.add(const Duration(hours: 5, minutes: 59))),
        isTrue,
      );
      expect(
        s.snoozed(start.add(const Duration(hours: 6, minutes: 1))),
        isFalse,
      );
    });

    test('failed relaunch falls back to manual reopen', () async {
      final t = make(restartOk: false);
      t.c.read(shorebirdUpdateProvider);
      await Future<void>.delayed(Duration.zero);
      final n = t.c.read(shorebirdUpdateProvider.notifier);
      await n.download();
      await n.restart();
      expect(t.c.read(shorebirdUpdateProvider).reopenByHand, isTrue);
    });
  });

  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget home, {
    FakeUpdater? u,
    bool disableAnimations = false,
  }) async {
    final t = make(u: u);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: t.c,
        child: MaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: disableAnimations),
            child: child!,
          ),
          home: home,
        ),
      ),
    );
    await tester.pump(_ms);
    await tester.pump(_ms);
    return t.c;
  }

  group('banner', () {
    const banner = Scaffold(
      body: Column(children: [ShorebirdUpdateBanner(), _Starter()]),
    );

    testWidgets('available -> Update -> ready -> Restart', (tester) async {
      final c = await pump(tester, banner);
      expect(find.text('Update available'), findsOneWidget);
      await tester.tap(find.text('Update'));
      await tester.pump(_ms);
      await tester.pump(_ms);
      expect(find.text('Update ready'), findsOneWidget);
      expect(find.text('Restart'), findsOneWidget);
      await tester.tap(find.text('Restart'));
      await tester.pump(_ms);
      expect(c.read(shorebirdUpdateProvider).reopenByHand, isFalse);
    });

    testWidgets('downloading shows an indeterminate bar', (tester) async {
      final c = await pump(tester, banner);
      c.read(shorebirdUpdateProvider.notifier).state =
          const ShorebirdUpdateState(phase: ShorebirdPhase.downloading);
      await tester.pump(_ms);
      expect(find.text('Downloading update…'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('shorebird-progress')),
      );
      expect(bar.value, isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('reduce motion drops the bar', (tester) async {
      final c = await pump(tester, banner, disableAnimations: true);
      c.read(shorebirdUpdateProvider.notifier).state =
          const ShorebirdUpdateState(phase: ShorebirdPhase.downloading);
      await tester.pump(_ms);
      expect(find.byKey(const ValueKey('shorebird-progress')), findsNothing);
    });

    testWidgets('failure shows retry', (tester) async {
      final c = await pump(tester, banner);
      c.read(shorebirdUpdateProvider.notifier).state =
          const ShorebirdUpdateState(phase: ShorebirdPhase.failed);
      await tester.pump(_ms);
      expect(find.text('Update failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('Later hides it', (tester) async {
      await pump(tester, banner);
      await tester.tap(find.text('Later'));
      await tester.pump(_ms);
      expect(find.byKey(const ValueKey('shorebird-banner')), findsNothing);
    });

    testWidgets('unavailable build renders nothing', (tester) async {
      await pump(tester, banner, u: FakeUpdater(available: false));
      expect(find.byKey(const ValueKey('shorebird-banner')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hidden while a route covers it', (tester) async {
      await pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                const ShorebirdUpdateBanner(),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(body: Text('covering')),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('shorebird-banner')), findsOneWidget);
      await tester.tap(find.text('open'));
      await tester.pump(_ms);
      await tester.pump(_ms);
      expect(find.byKey(const ValueKey('shorebird-banner')), findsNothing);
    });
  });

  group('settings', () {
    testWidgets('unavailable row + version line + copy', (tester) async {
      await pump(
        tester,
        const SettingsScreen(),
        u: FakeUpdater(available: false),
      );
      expect(find.text('Check for updates'), findsOneWidget);
      expect(
        find.text("Updates aren't available in this build"),
        findsOneWidget,
      );
      final line = 'Version $appVersion (build $appBuildNumber) · patch 0';
      expect(find.text(line), findsOneWidget);

      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.longPress(find.text(line));
      await tester.pump();
      expect(copied, '$appVersion+$appBuildNumber · patch 0');
    });

    testWidgets('idle row shows patch and tap forces a check', (tester) async {
      final u = FakeUpdater(status: UpdateStatus.upToDate);
      await pump(tester, const SettingsScreen(), u: u);
      expect(find.text('Patch 3'), findsOneWidget);
      final before = u.checks;
      await tester.tap(find.byKey(const ValueKey('update-row')));
      await tester.pump(_ms);
      expect(u.checks, before + 1);
      expect(find.text("You're up to date."), findsOneWidget);
    });

    testWidgets('available row tap downloads', (tester) async {
      final u = FakeUpdater();
      await pump(tester, const SettingsScreen(), u: u);
      expect(find.text('Update available'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('update-row')));
      await tester.pump(_ms);
      expect(u.updates, 1);
    });
  });
}

/// Starts the check the way the Chats home does (watch the provider).
class _Starter extends ConsumerWidget {
  const _Starter();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(shorebirdUpdateProvider);
    return const SizedBox.shrink();
  }
}
