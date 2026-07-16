import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/debug_chat/debug_chat_screen.dart';

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
    // Loop 2: the engine-debug harness is the temporary home. Real routing +
    // theming (design-tokens.json) land in later loops.
    return MaterialApp(
      title: 'Dhruva',
      theme: ThemeData(useMaterial3: true),
      home: const DebugChatScreen(),
    );
  }
}
