// On-device check of the opt-in crash log: an uncaught Flutter error is
// written to the real app-support dir, the Chats banner offers to send it,
// and Settings → Crash reports lists it. Nothing is sent.
//
// Run: flutter test integration_test/crash_report_test.dart -d <id>
import 'package:dhruva/core/crash/crash_log.dart';
import 'package:dhruva/core/router/app_router.dart';
import 'package:dhruva/features/onboarding/state/onboarding_controller.dart';
import 'package:dhruva/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('uncaught error → logged on disk → banner + list', (
    tester,
  ) async {
    final log = CrashLog(appVersion: 'it', appBuild: '0');
    await log.clear();

    // Same hook main() installs; the test binding owns FlutterError.onError,
    // so call through the installed handler and restore afterwards.
    final testHandler = FlutterError.onError;
    FlutterError.onError = null;
    log.install();
    final hooked = FlutterError.onError!;
    FlutterError.onError = testHandler;
    hooked(
      FlutterErrorDetails(
        exception: StateError('on-device crash probe'),
        stack: StackTrace.current,
        silent: true,
      ),
    );
    await log.record(StateError('flush'), null); // waits for the queue
    final all = await log.readAll();
    expect(all.map((r) => r.message), contains(contains('crash probe')));

    final container = ProviderContainer(
      overrides: [crashLogProvider.overrideWithValue(log)],
    );
    addTearDown(container.dispose);
    await (await container.read(onboardingStoreProvider.future)).markComplete();

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const DhruvaApp()),
    );
    appRouter.go('/chat');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('crash-banner')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('crash-dismiss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('crash-banner')), findsNothing);

    appRouter.go('/settings/crash-reports');
    await tester.pumpAndSettle();
    expect(find.text('StateError'), findsWidgets);

    await log.clear();
  });
}
