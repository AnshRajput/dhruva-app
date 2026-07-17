/// Bottom-nav shell for the four top-level destinations (Loop 4 + Amendment
/// 4b + Loop 5). Not specified by chat-spec.md (it only covers the chat
/// screens themselves) — per the Loop-4 brief's fallback, a plain
/// `NavigationBar`. `/chat` is app home per chat-spec.md §1; characters,
/// models hub, and settings are the second/third/fourth destinations. Detail
/// routes (`/chat/:id`, `/characters/:id`, `/models/repo/:id`,
/// `/models/downloads`) are pushed as siblings of this shell (see
/// `app_router.dart`), so they cover the nav bar full-screen rather than
/// nesting inside it.
///
/// Amendment 4b: the Models destination carries a live badge whenever any
/// download is active (queued/running/paused/verifying) — reuses
/// `DownloadsController`'s existing progress-stream accumulation rather than
/// standing up a second subscription to `DownloadManager.progress`. This is
/// the app's one composition root that's allowed to import feature code
/// directly (`app_router.dart` already imports every top-level screen the
/// same way), so reaching into `features/models_hub`'s provider here doesn't
/// breach ADR-002's cross-feature-import rule the way a features/settings ->
/// features/chat import would.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/downloads/download_manager.dart';
import '../../features/models_hub/state/downloads_controller.dart';

class AppShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  const AppShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadsControllerProvider).value ?? const {};
    final hasActiveDownload = downloads.values.any(_isActive);

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          const NavigationDestination(
            icon: Icon(Icons.theater_comedy_outlined),
            selectedIcon: Icon(Icons.theater_comedy),
            label: 'Characters',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: hasActiveDownload,
              smallSize: 8,
              child: const Icon(Icons.widgets_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: hasActiveDownload,
              smallSize: 8,
              child: const Icon(Icons.widgets),
            ),
            label: 'Models',
            tooltip: hasActiveDownload
                ? 'Models — download in progress'
                : 'Models',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

bool _isActive(DownloadProgress progress) => switch (progress.state) {
  DownloadState.queued ||
  DownloadState.running ||
  DownloadState.paused ||
  DownloadState.verifying => true,
  DownloadState.complete ||
  DownloadState.failed ||
  DownloadState.canceled => false,
};
