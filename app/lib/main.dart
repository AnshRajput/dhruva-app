import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/onboarding/state/onboarding_controller.dart';

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
  final container = ProviderContainer();
  try {
    final done = await container.read(onboardingCompleteProvider.future);
    if (!done) appRouter.go('/onboarding');
  } catch (_) {
    // Onboarding is a nicety, not a gate — fall through to chat on any error.
  }

  runApp(
    UncontrolledProviderScope(container: container, child: const DhruvaApp()),
  );
}

class DhruvaApp extends StatelessWidget {
  const DhruvaApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Real theming from design-tokens.json (ADR-003). Dark is the
    // hero/default — `meta.defaultTheme` is "dark" and the website the app
    // must match is dark, so we pin `themeMode.dark` (not `.system`): that is
    // what makes the app open in the striking navy/gold palette the mockups
    // show, instead of the flat light theme a light-preference device was
    // defaulting into. The light theme still exists (`AppTheme.light`, kept
    // as `theme:`) for a future in-app appearance toggle; every screen reads
    // Theme.of(context)'s semantic roles, so both modes light up unchanged.
    return MaterialApp.router(
      title: 'Dhruva',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: appRouter,
    );
  }
}
