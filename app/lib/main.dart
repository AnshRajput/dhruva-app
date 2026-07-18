import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

void main() {
  // Loop 3: ProviderScope wraps the app so core/di/providers.dart's
  // providers (EngineService, AppDatabase, HfApiClient, DownloadManager,
  // StorageManager) are reachable from features/. `debug_chat` (the one
  // documented exception, per Loop 2/3) was deleted in Loop 4 — its
  // developer-harness role is now the real chat feature.
  runApp(const ProviderScope(child: DhruvaApp()));
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
