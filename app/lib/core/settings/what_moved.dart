/// "What moved" one-time sheet for users upgrading from 0.6.x (daily-assistant
/// Wave 1). Pending until dismissed; the dismissed flag persists in
/// [PrefsStore]. A fresh install never sees it: onboarding marks it dismissed
/// when it finishes or is skipped (there is nothing to have moved for a new
/// user).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/dhruva_theme_extension.dart';
import '../widgets/dhruva_sheet.dart';
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
    // Let build() resolve first, or it lands after us and overwrites the
    // dismissal with "pending" (the flag is not on disk yet).
    await future;
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
      await showDhruvaSheet<void>(
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
    final tokens = theme.extension<DhruvaTokens>()!;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          tokens.spacing.lg,
          0,
          tokens.spacing.lg,
          tokens.spacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What moved', style: theme.textTheme.headlineSmall),
            SizedBox(height: tokens.spacing.xs),
            Text(
              'Everything is still here, in new places.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: tokens.spacing.base),
            for (final card in whatMovedCards)
              Padding(
                padding: EdgeInsets.only(bottom: tokens.spacing.md),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(tokens.radius.xl),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(tokens.spacing.base),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(card.icon, color: theme.colorScheme.primary),
                        SizedBox(width: tokens.spacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                card.title,
                                style: theme.textTheme.titleSmall,
                              ),
                              SizedBox(height: tokens.spacing.xs / 2),
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
            SizedBox(height: tokens.spacing.xs),
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
