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
    // Loop 4: real theming from design-tokens.json (ADR-003). Dark is the
    // hero/default (design-tokens.json meta.defaultTheme); themeMode.system
    // still lets a light-preference device get the recalibrated light
    // theme. Every screen already reads Theme.of(context)'s semantic roles,
    // so both modes light up for free — see the designer's spot-check note
    // on the Loop-4 blackboard entry for any role-misuse fixes.
    return MaterialApp.router(
      title: 'Dhruva',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
    );
  }
}
