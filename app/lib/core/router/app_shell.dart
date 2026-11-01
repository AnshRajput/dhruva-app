/// Bottom-nav shell for the daily-assistant tabs: Today · Inbox · Ask ·
/// Library. The Inbox tab is hidden until an inbox source exists
/// (`inboxAvailableProvider`); Today carries a "Set up your inbox" card
/// meanwhile. Settings is NOT a tab: it opens full-screen from the gear on
/// Today. Detail routes (`/chat/:id`, `/settings/*`, `/models/*`, ...) are
/// pushed as siblings of this shell (see `app_router.dart`), so they cover the
/// nav bar full-screen rather than nesting inside it, and they must never push
/// a shell-branch route (the 0.6.0 blank-page bug).
///
/// This always-mounted composition root is the one place allowed to import
/// feature code directly (ADR-002), so reaching into `features/models_hub`'s
/// download provider here doesn't breach the cross-feature-import rule.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/benchmark/speed_result.dart';
import '../../data/downloads/download_manager.dart';
import '../../data/models/starter_catalog.dart';
import '../../features/characters/state/installed_models_provider.dart'
    as char_installed;
import '../../features/chat/state/installed_models_provider.dart'
    as chat_installed;
import '../../features/models_hub/state/downloads_controller.dart';
import '../../features/models_hub/state/speed_test_controller.dart';
import '../../features/models_hub/state/storage_controller.dart';
import '../../features/playground/state/playground_installed_models_provider.dart'
    as playground_installed;
import '../settings/what_moved.dart';
import '../widgets/platform_chrome.dart';
import 'inbox_availability.dart';

/// Branch indexes in the shell (order of `StatefulShellRoute` branches).
abstract final class ShellBranch {
  static const today = 0;
  static const inbox = 1;
  static const ask = 2;
  static const library = 3;
}

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
        // One-time, dismissible offer — shown on the Installed tab.
        ref
            .read(speedTestOfferProvider.notifier)
            .offer(speedKey(readyRepo, readyFile));
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

    final inboxAvailable = ref.watch(inboxAvailableProvider);
    final glass = useGlassChrome(context, ref);

    // Visible tabs -> shell branch indexes. With the Inbox hidden, branch 1
    // is unreachable from the bar; if a deep link lands there, Today is
    // highlighted (the Inbox screen then shows its connect state).
    final branches = <int>[
      ShellBranch.today,
      if (inboxAvailable) ShellBranch.inbox,
      ShellBranch.ask,
      ShellBranch.library,
    ];
    final selected = branches.indexOf(navigationShell.currentIndex);

    return Scaffold(
      // iOS glass: content scrolls under the translucent tab bar.
      extendBody: glass,
      body: WhatMovedGate(child: navigationShell),
      bottomNavigationBar: AdaptiveTabBar(
        selectedIndex: selected < 0 ? 0 : selected,
        onSelected: (index) => navigationShell.goBranch(
          branches[index],
          initialLocation: branches[index] == navigationShell.currentIndex,
        ),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.wb_sunny_outlined),
            selectedIcon: Icon(Icons.wb_sunny),
            label: 'Today',
          ),
          if (inboxAvailable)
            const NavigationDestination(
              icon: Icon(Icons.inbox_outlined),
              selectedIcon: Icon(Icons.inbox),
              label: 'Inbox',
            ),
          const NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Ask',
          ),
          const NavigationDestination(
            icon: Icon(Icons.local_library_outlined),
            selectedIcon: Icon(Icons.local_library),
            label: 'Library',
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
    navigationShell.goBranch(ShellBranch.ask);
  }
}

Set<String> _completedTaskIds(
  AsyncValue<Map<String, DownloadProgress>>? value,
) => (value?.value ?? const <String, DownloadProgress>{}).entries
    .where((e) => e.value.state == DownloadState.complete)
    .map((e) => e.key)
    .toSet();
