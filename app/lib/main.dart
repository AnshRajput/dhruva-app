import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';

void main() {
  // Loop 3: ProviderScope wraps the app so core/di/providers.dart's
  // providers (EngineService, AppDatabase, HfApiClient, DownloadManager,
  // StorageManager) are reachable from features/. debug_chat is the one
  // documented exception — it still constructs its own EngineService (see
  // its file header) and doesn't read from providers.
  runApp(const ProviderScope(child: DhruvaApp()));
}

class DhruvaApp extends StatelessWidget {
  const DhruvaApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Loop 3: models_hub is the app home via go_router. Plain Material 3 —
    // real theming (design-tokens.json) lands in Loop 4; every color here
    // comes from Theme.of(context)'s semantic roles so it re-themes for
    // free.
    return MaterialApp.router(
      title: 'Dhruva',
      theme: ThemeData(useMaterial3: true),
      routerConfig: appRouter,
    );
  }
}
