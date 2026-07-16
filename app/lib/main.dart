import 'package:flutter/material.dart';

import 'features/debug_chat/debug_chat_screen.dart';

void main() {
  runApp(const DhruvaApp());
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
