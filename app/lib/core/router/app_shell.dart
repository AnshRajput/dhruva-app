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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/downloads/download_manager.dart';
import '../../data/models/starter_catalog.dart';
import '../../features/characters/state/installed_models_provider.dart'
    as char_installed;
import '../../features/chat/state/installed_models_provider.dart'
    as chat_installed;
import '../../features/models_hub/state/downloads_controller.dart';
import '../../features/models_hub/state/storage_controller.dart';
import '../../features/playground/state/playground_installed_models_provider.dart'
    as playground_installed;

class AppShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  const AppShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // UX-hardening A1 + A5. This always-mounted composition root is the one
    // place allowed to import feature code (see the header + ADR-002). When a
    // download completes, invalidate EVERY read-only installed-model provider
    // so a freshly-downloaded model appears without an app restart — the chat
    // picker/composer, the character default-model picker, the Models
    // "Installed" tab, and the Downloads "Installed" section all read one of
    // these three. This is the shipped app's #1 "downloaded a model but still
    // can't start a convo" bug. Diff prev/next completed-set so it fires once
    // per NEW completion, not on every later progress tick.
    ref.listen(downloadsControllerProvider, (prev, next) {
      final newly = _completedTaskIds(next).difference(_completedTaskIds(prev));
      if (newly.isEmpty) return;
      ref.invalidate(chat_installed.installedModelsProvider);
      ref.invalidate(char_installed.installedModelsProvider);
      ref.invalidate(playground_installed.playgroundInstalledModelsProvider);
      ref.invalidate(storageControllerProvider);

      // A5: an unmissable confirmation that ties the loop back to chatting —
      // but only for chat-usable GGUF models that are FULLY ready. Voice
      // bundles ride the same download pipeline (sherpa-voice/ repoId) yet
      // aren't a chat pick; they have their own Voice tab, so don't tell the
      // user to "start chatting".
      //
      // Vision (WS4): a vision model's GGUF completing does NOT make it
      // chat-ready — its mmproj projector still has to download + attach. So
      // announce a vision model only when its PROJECTOR completes (both files
      // on disk), not when the model file alone finishes. The projector rides
      // the pipeline with registerAsInstalledModel: false and shares the
      // model's repoId, so on its completion we resolve the paired,
      // already-complete model file from the accumulated map.
      final map = next.value ?? const <String, DownloadProgress>{};
      DownloadProgress? model;
      for (final id in newly) {
        final p = map[id];
        if (p == null || p.repoId.startsWith('sherpa-voice/')) continue;
        if (p.registerAsInstalledModel) {
          if (p.isVision) continue; // wait for the projector, below.
          model = p;
          break;
        }
        // A projector just landed → the paired vision model is now ready.
        final paired = map.values
            .where(
              (m) =>
                  m.repoId == p.repoId &&
                  m.isVision &&
                  m.registerAsInstalledModel &&
                  m.state == DownloadState.complete,
            )
            .firstOrNull;
        if (paired != null) {
          model = paired;
          break;
        }
      }
      if (model != null) {
        final readyRepo = model.repoId;
        final readyFile = model.fileName;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                '${friendlyModelName(model.repoId)} is ready — start chatting.',
              ),
              action: SnackBarAction(
                label: 'Start chatting',
                // Direct CTA into a chat already LOADED with the model that
                // just finished — resolve its drift row (invalidated fresh
                // above) and push /chat/new with it, rather than dropping the
                // user on the chat tab to re-pick it.
                onPressed: () => unawaited(
                  _openChatWith(
                    context,
                    ref,
                    navigationShell,
                    readyRepo,
                    readyFile,
                  ),
                ),
              ),
            ),
          );
      }
    });

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
            icon: Icon(Icons.science_outlined),
            selectedIcon: Icon(Icons.science),
            label: 'Playground',
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

/// Opens a chat loaded with the just-downloaded model. Resolves its drift row
/// (freshly invalidated on completion) by repoId+fileName; falls back to the
/// chat branch's own new-chat flow if the row can't be resolved yet.
Future<void> _openChatWith(
  BuildContext context,
  WidgetRef ref,
  StatefulNavigationShell navigationShell,
  String repoId,
  String fileName,
) async {
  final models = await ref.read(chat_installed.installedModelsProvider.future);
  final id = models
      .where((m) => m.repoId == repoId && m.fileName == fileName)
      .map((m) => m.id)
      .firstOrNull;
  if (!context.mounted) return;
  if (id != null) {
    unawaited(context.push('/chat/new', extra: id));
  } else {
    navigationShell.goBranch(0);
  }
}

Set<String> _completedTaskIds(
  AsyncValue<Map<String, DownloadProgress>>? value,
) => (value?.value ?? const <String, DownloadProgress>{}).entries
    .where((e) => e.value.state == DownloadState.complete)
    .map((e) => e.key)
    .toSet();

bool _isActive(DownloadProgress progress) => switch (progress.state) {
  DownloadState.queued ||
  DownloadState.running ||
  DownloadState.paused ||
  DownloadState.verifying => true,
  DownloadState.complete ||
  DownloadState.failed ||
  DownloadState.canceled => false,
};
