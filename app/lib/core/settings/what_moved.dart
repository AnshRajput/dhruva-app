/// "What moved" one-time sheet for users upgrading from 0.6.x (daily-assistant
/// Wave 1). Pending until dismissed; the dismissed flag persists in
/// [PrefsStore]. A fresh install never sees it: onboarding marks it dismissed
/// when it finishes or is skipped (there is nothing to have moved for a new
/// user).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'prefs_store.dart';

const whatMovedDismissedKey = 'what_moved_dismissed';

/// Value is `true` while the sheet is still owed to the user.
class WhatMovedNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final store = await ref.watch(prefsStoreProvider.future);
    return (await store.read(whatMovedDismissedKey)) != 'true';
  }

  Future<void> dismiss() async {
    final store = await ref.read(prefsStoreProvider.future);
    state = const AsyncData(false);
    await store.write(whatMovedDismissedKey, 'true');
  }
}

final whatMovedPendingProvider = AsyncNotifierProvider<WhatMovedNotifier, bool>(
  WhatMovedNotifier.new,
);

/// The three cards. Kept as data so the copy is testable.
const whatMovedCards = <({IconData icon, String title, String body})>[
  (
    icon: Icons.chat_bubble_outline_rounded,
    title: 'Chat is now Ask',
    body: 'Your chats, folders and pins are all in the Ask tab.',
  ),
  (
    icon: Icons.tune_rounded,
    title: 'Models and Playground are in Settings',
    body:
        'Open the gear on Today, then Models. Downloads, voice, compare and '
        'AI news are there too.',
  ),
  (
    icon: Icons.auto_awesome_outlined,
    title: 'Workflows are now Actions',
    body:
        'Same one-tap tools, now inside Ask and on Today. Share sheet and '
        'text selection still land there.',
  ),
];

/// Wraps the shell body: shows the sheet once, on the first frame where it is
/// pending, then records the dismissal however the sheet is closed.
class WhatMovedGate extends ConsumerStatefulWidget {
  const WhatMovedGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WhatMovedGate> createState() => _WhatMovedGateState();
}

class _WhatMovedGateState extends ConsumerState<WhatMovedGate> {
  bool _shown = false;

  void _maybeShow() {
    if (_shown) return;
    if (ref.read(whatMovedPendingProvider).value != true) return;
    _shown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const WhatMovedSheet(),
      );
      if (mounted) await ref.read(whatMovedPendingProvider.notifier).dismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(whatMovedPendingProvider, (_, _) => _maybeShow());
    // Covers the case where the value is already loaded when we mount.
    _maybeShow();
    return widget.child;
  }
}

class WhatMovedSheet extends StatelessWidget {
  const WhatMovedSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What moved', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Everything is still here, in new places.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            for (final card in whatMovedCards)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(card.icon, color: theme.colorScheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                card.title,
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                card.body,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
