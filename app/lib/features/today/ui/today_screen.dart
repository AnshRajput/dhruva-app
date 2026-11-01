/// Today (`/today`): the daily-assistant home, direction A ("calm brief") from
/// the approved comps, with B's timeline behind "See day".
///
/// Wave 1 ships the STRUCTURE with honest placeholders: greeting + date, a
/// brief card that explains it appears once the calendar is connected, the
/// quick-actions row wired to Actions, an "Up next" block, and a "Set up your
/// inbox" card (the Inbox tab is hidden until a source exists). Every empty
/// state has a working next action. Real data lands in Wave 3.
///
/// All navigation from here pushes FULL-SCREEN routes only (`/settings`,
/// `/actions`, `/day`, `/inbox/connect`, ...), never a shell-branch route.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/identity/app_identity.dart';
import '../../../core/theme/brand_star.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/next_step_card.dart';
import '../../../core/widgets/platform_chrome.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../state/day_text.dart';

/// Max characters of clipboard text carried in the router URL (mirrors the
/// share-sheet bound in `IntentInbox`; Actions trims to the model context).
const _maxClipboardChars = 16000;

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key, this.statusPill, this.now});

  /// Optional download status pill, injected by the composition root so
  /// `features/today` never imports `features/models_hub` (ADR-002).
  final Widget? statusPill;

  /// Test seam for the greeting/date.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final today = now ?? DateTime.now();
    final scheme = theme.colorScheme;

    return ChromeScaffold(
      appBar: AdaptiveAppBar(
        automaticallyImplyLeading: false,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DhruvaStar(size: 16, color: scheme.primary),
            SizedBox(width: tokens.spacing.sm),
            Text(AppIdentity.wordmark, style: theme.textTheme.titleLarge),
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey('today-settings'),
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
          SizedBox(width: tokens.spacing.xs),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          tokens.spacing.base,
          tokens.spacing.xs,
          tokens.spacing.base,
          tokens.spacing.xl2,
        ),
        children: [
          Text(greetingFor(today), style: theme.textTheme.headlineMedium),
          SizedBox(height: tokens.spacing.xs),
          Text(
            formatDayLine(today),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (statusPill != null) ...[
            SizedBox(height: tokens.spacing.sm),
            Align(alignment: Alignment.centerLeft, child: statusPill),
          ],
          SizedBox(height: tokens.spacing.base),
          const _BriefCard(),
          SizedBox(height: tokens.spacing.base),
          const _QuickActionsRow(),
          SizedBox(height: tokens.spacing.lg),
          _SectionHeader(
            title: 'Up next',
            actionLabel: 'See day',
            actionKey: const ValueKey('today-see-day'),
            onAction: () => context.push('/day'),
          ),
          SizedBox(height: tokens.spacing.sm),
          NextStepCard(
            icon: Icons.event_outlined,
            title: 'Nothing scheduled yet',
            body:
                'Connect your calendar to see your next meetings here. It '
                'needs no sign-in and never leaves this phone.',
            actionLabel: 'Connect calendar',
            actionKey: const ValueKey('today-connect-calendar'),
            onAction: () => context.push('/settings/connectors'),
          ),
          SizedBox(height: tokens.spacing.lg),
          const _SectionHeader(title: 'Needs you'),
          SizedBox(height: tokens.spacing.sm),
          NextStepCard(
            icon: Icons.inbox_outlined,
            title: 'Set up your inbox',
            body:
                'Mail and notifications that need a reply, in one calm list '
                'with a drafted answer you edit and send yourself.',
            actionLabel: 'Set up inbox',
            actionKey: const ValueKey('today-setup-inbox'),
            // Full-screen route, NOT the shell's /inbox branch.
            onAction: () => context.push('/inbox/connect'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
    this.actionKey,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
        if (actionLabel != null)
          TextButton(
            key: actionKey,
            onPressed: onAction,
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

/// Brief placeholder. In Wave 3 this becomes the on-device written brief with
/// tappable, cited phrases; until then it says exactly when it will appear.
class _BriefCard extends StatelessWidget {
  const _BriefCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;
    return DecoratedBox(
      key: const ValueKey('today-brief'),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(tokens.radius.xl),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DhruvaStar(size: 12, color: scheme.primary),
                SizedBox(width: tokens.spacing.sm),
                Text(
                  'Your brief',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
            SizedBox(height: tokens.spacing.md),
            Text(
              'Your brief appears here once you connect your calendar.',
              style: theme.textTheme.titleLarge,
            ),
            SizedBox(height: tokens.spacing.sm),
            Row(
              children: [
                Icon(Icons.lock_outline, size: 14, color: tokens.success),
                SizedBox(width: tokens.spacing.xs),
                Expanded(
                  child: Text(
                    'Written on this phone from your day. Nothing is uploaded.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: tokens.spacing.base),
            FilledButton(
              key: const ValueKey('today-brief-connect'),
              onPressed: () => context.push('/settings/connectors'),
              child: const Text('Connect calendar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal one-tap row wired to Actions (the old Workflows). Each chip
/// opens `/actions?id=<workflow>`, the same route the share sheet lands on.
class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow();

  static const _actions = <(String, IconData, String)>[
    ('summarize', Icons.content_paste_rounded, 'Summarize clipboard'),
    ('draft_reply', Icons.edit_outlined, 'Draft reply'),
    ('todos', Icons.checklist_rounded, 'Extract to-dos'),
  ];

  Future<void> _open(BuildContext context, String id) async {
    if (id != 'summarize') {
      await context.push('/actions?id=$id');
      return;
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    var text = data?.text?.trim() ?? '';
    if (!context.mounted) return;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Clipboard is empty. Copy some text, or paste it in.'),
        ),
      );
      await context.push('/actions?id=summarize');
      return;
    }
    if (text.length > _maxClipboardChars) {
      text = text.substring(0, _maxClipboardChars);
    }
    await context.push(
      '/actions?id=summarize&text=${Uri.encodeQueryComponent(text)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return SizedBox(
      height: 48,
      child: ListView(
        key: const ValueKey('today-quick-actions'),
        scrollDirection: Axis.horizontal,
        children: [
          for (final (id, icon, label) in _actions) ...[
            PressableScale(
              onTap: () => _open(context, id),
              semanticLabel: label,
              child: _Pill(
                icon: icon,
                label: label,
                keyValue: 'today-action-$id',
              ),
            ),
            SizedBox(width: tokens.spacing.sm),
          ],
          PressableScale(
            onTap: () => context.push('/actions'),
            semanticLabel: 'All actions',
            child: const _Pill(
              icon: Icons.arrow_forward_rounded,
              label: 'All actions',
              keyValue: 'today-action-all',
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.keyValue,
  });

  final IconData icon;
  final String label;
  final String keyValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return DecoratedBox(
      key: ValueKey(keyValue),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(tokens.radius.full),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: tokens.spacing.base),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            SizedBox(width: tokens.spacing.sm),
            Text(label, style: theme.textTheme.labelLarge),
          ],
        ),
      ),
    );
  }
}
