import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/crash/crash_log.dart';
import 'core/di/connector_providers.dart';
import 'core/di/speed_providers.dart';
import 'core/identity/app_identity.dart';
import 'core/intents/intent_inbox.dart';
import 'core/intents/process_text.dart';
import 'core/notifications/morning_brief.dart';
import 'core/privacy/screen_privacy.dart';
import 'core/profile/user_profile.dart';
import 'core/router/app_router.dart';
import 'core/settings/bool_pref.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/appearance_providers.dart';
import 'features/onboarding/state/onboarding_controller.dart';
import 'features/settings/app_info.dart';

Future<void> main() async {
  // Loop 3: ProviderScope wraps the app so core/di/providers.dart's
  // providers (EngineService, AppDatabase, HfApiClient, DownloadManager,
  // StorageManager) are reachable from features/. `debug_chat` (the one
  // documented exception, per Loop 2/3) was deleted in Loop 4 — its
  // developer-harness role is now the real chat feature.
  WidgetsFlutterBinding.ensureInitialized();
  // The real version, from the bundled pubspec (About line, crash log, reports).
  await loadAppVersion();

  // WS2: on a fresh install, send the user into the guided onboarding flow
  // before the first frame. Read the "onboarding done" flag ONCE here (not a
  // live router redirect — see app_router.dart) via a container we then hand
  // to the app so the flag store isn't rebuilt. A read failure never blocks
  // launch: default to chat.
  // Opt-in local crash log: records to disk, never sends anything.
  final crashLog = CrashLog(appVersion: appVersion, appBuild: appBuildNumber)
    ..install();
  final container = ProviderContainer(
    overrides: [
      crashLogProvider.overrideWithValue(crashLog),
      appVersionProvider.overrideWithValue(appVersion),
    ],
  );
  // The four startup reads are independent, so they run TOGETHER: first frame
  // waits for the slowest, not the sum (a widget/tile launch showed a black
  // frame for seconds). Each failure is swallowed on its own.
  Future<void> guarded(Future<void> Function() read) async {
    try {
      await read();
    } catch (_) {
      // Every one of these is a nicety, never a gate on launch.
    }
  }

  await Future.wait([
    // Onboarding is a nicety, not a gate: fall through to Today on any error.
    guarded(() async {
      final done = await container.read(onboardingCompleteProvider.future);
      if (!done) appRouter.go('/onboarding');
    }),
    // Load the saved theme mode before the first frame so a user who chose
    // Light/Dark never sees a flash of the system theme.
    guarded(() => container.read(themeModeProvider.future)),
    // Warm the "About the user" prompt block so the first send has it.
    guarded(() => container.read(userContextProvider.future)),
    // "Hide content in app switcher" must be in force before the first frame
    // is ever snapshotted; DhruvaApp keeps it in sync after that.
    guarded(() async {
      final hidden = await container.read(hideInAppSwitcherProvider.future);
      await container.read(screenPrivacyProvider).setHidden(hidden);
    }),
  ]);

  runApp(
    UncontrolledProviderScope(container: container, child: const DhruvaApp()),
  );

  // Android share / text-selection / shortcut entry points -> router.
  // After the first frame, so the router has consumed its initial location
  // and a cold-start share/selection isn't overwritten by it.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(
      IntentInbox(
        navigate: navigateFromIntent,
        onReplaceable: container.read(processTextSessionProvider.notifier).set,
      ).start(),
    );
    // Morning brief: wire the notification tap to Today and top up the next
    // mornings while the brief is on. Never blocks or breaks launch.
    unawaited(_startMorningBrief(container));
    // Connectors (Wave 2A): pick the search engine, refresh statuses, sync
    // what is stale, schedule the Android background job. Never blocks or
    // breaks launch.
    unawaited(
      container
          .read(connectorBootstrapProvider.future)
          .then((_) {}, onError: (Object _) {}),
    );
  });
}

Future<void> _startMorningBrief(ProviderContainer container) async {
  try {
    final enabled = await container.read(morningBriefEnabledProvider.future);
    final minutes = await container.read(morningBriefMinutesProvider.future);
    await startMorningBrief(
      gateway: container.read(notificationGatewayProvider),
      scheduler: container.read(morningBriefSchedulerProvider),
      enabled: enabled,
      minutesAfterMidnight: minutes,
      // Today is a shell branch: `go`, never `push`.
      openToday: () => appRouter.go('/today'),
    );
  } on Object {
    // A notification problem never blocks launch.
  }
}

/// Intent targets that are shell branches (`/today`, `/ask`, ...) must `go`:
/// pushing one builds a second shell whose branch renders blank.
void navigateFromIntent(String location) {
  if (isShellLocation(location)) {
    appRouter.go(location);
  } else {
    unawaited(appRouter.push(location));
  }
}

class DhruvaApp extends ConsumerWidget {
  const DhruvaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Saved choice (Settings > Appearance); until it loads (or if it can't),
    // follow the system.
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.system;
    // Settings > Privacy: apply every toggle (Android FLAG_SECURE / iOS
    // cover view); the saved value is applied in main() before the first frame.
    ref.listen(hideInAppSwitcherProvider, (_, next) {
      final hidden = next.value;
      if (hidden != null) {
        unawaited(ref.read(screenPrivacyProvider).setHidden(hidden));
      }
    });
    // Refresh connector statuses whenever the app comes back to the
    // foreground (access granted in system settings shows up at once).
    ref.watch(connectorResumeProvider);
    // Real theming from design-tokens.json (ADR-003). Follows the system
    // light/dark by default (the owner-approved daily-assistant direction);
    // Settings > Appearance can pin Light or Dark. Every screen reads
    // Theme.of(context)'s semantic roles, so both modes light up unchanged.
    return MaterialApp.router(
      title: AppIdentity.productName,
      // The debug ribbon otherwise lands in every debug-build capture, which
      // makes store screenshots and design review unusable.
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      // Status bar style follows the theme on every route (iOS clock was
      // invisible on light screens). AppBars carry the same style themselves.
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlayStyleFor(Theme.of(context).brightness),
        child: child ?? const SizedBox.shrink(),
      ),
      routerConfig: appRouter,
    );
  }
}
