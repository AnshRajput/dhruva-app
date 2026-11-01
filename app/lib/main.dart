import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/crash/crash_log.dart';
import 'core/di/speed_providers.dart';
import 'core/identity/app_identity.dart';
import 'core/intents/intent_inbox.dart';
import 'core/router/app_router.dart';
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
  try {
    final done = await container.read(onboardingCompleteProvider.future);
    if (!done) appRouter.go('/onboarding');
  } catch (_) {
    // Onboarding is a nicety, not a gate — fall through to Today on any error.
  }
  try {
    // Load the saved theme mode before the first frame so a user who chose
    // Light/Dark never sees a flash of the system theme.
    await container.read(themeModeProvider.future);
  } catch (_) {
    // Unreadable prefs fall back to following the system.
  }

  runApp(
    UncontrolledProviderScope(container: container, child: const DhruvaApp()),
  );

  // Android share / text-selection / shortcut entry points -> router.
  // After the first frame, so the router has consumed its initial location
  // and a cold-start share/selection isn't overwritten by it.
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => unawaited(IntentInbox(navigate: navigateFromIntent).start()),
  );
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
      routerConfig: appRouter,
    );
  }
}
