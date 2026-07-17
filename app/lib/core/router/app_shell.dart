/// Bottom-nav shell for the two top-level destinations (Loop 4). Not
/// specified by chat-spec.md (it only covers the chat screens themselves) —
/// per the Loop-4 brief's fallback, a plain `NavigationBar` with Chat/Models
/// destinations. `/chat` is app home per chat-spec.md §1; models hub moves
/// here as the second destination. Detail routes (`/chat/:id`,
/// `/models/repo/:id`, `/models/downloads`) are pushed as siblings of this
/// shell (see `app_router.dart`), so they cover the nav bar full-screen
/// rather than nesting inside it.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const AppShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.widgets_outlined),
            selectedIcon: Icon(Icons.widgets),
            label: 'Models',
          ),
        ],
      ),
    );
  }
}
