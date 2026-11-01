/// "Needs you" (people writing to you, found by rules, until Gmail exists) and
/// the Android-only notification digest. Both read the notification groups the
/// Wave 2A connector keeps on the phone; "Mark all read" is a local flag.
/// Nothing renders when there is nothing to show (no empty shell).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/connector_providers.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../data/connectors/connector.dart';
import '../state/brief_facts.dart';
import '../state/today_data.dart';
import 'today_sheets.dart';
import 'today_widgets.dart';

class NeedsYouSection extends ConsumerWidget {
  const NeedsYouSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(notificationGroupsProvider).value ?? const [];
    final now = ref.watch(todayClockProvider)();
    final entries = needsYou(groups, now);
    if (entries.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: tokens.spacing.lg),
        SectionHeader(
          title: 'Needs you',
          trailing: '${entries.length} waiting',
        ),
        SizedBox(height: tokens.spacing.sm),
        for (final (i, e) in entries.indexed)
          PressableScale(
            onTap: () => showNotificationSheet(context, e.group),
            semanticLabel:
                '${e.item.title} on ${e.group.appLabel}: ${e.item.body}',
            child: Padding(
              key: ValueKey('needs-you-$i'),
              padding: EdgeInsets.symmetric(vertical: tokens.spacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PersonAvatar(name: e.item.title, size: 44, colorIndex: i),
                  SizedBox(width: tokens.spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                e.item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            SizedBox(width: tokens.spacing.sm),
                            Text(
                              e.group.appLabel,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              formatClock(
                                context,
                                e.item.sentAt ?? e.item.updatedAt,
                              ),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          e.item.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
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
      ],
    );
  }
}

/// Notifications by app, one line each. Android only, and only when the
/// connector is on (or needs its access switched back on).
class DigestCard extends ConsumerWidget {
  const DigestCard({super.key});

  static const _maxRows = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(notificationsEntryProvider);
    if (entry == null) return const SizedBox.shrink(); // iOS / not offered
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;
    final status = entry.status;

    if (status.state == ConnectorState.needsAttention) {
      return Padding(
        padding: EdgeInsets.only(top: tokens.spacing.lg),
        child: TodayCard(
          cardKey: const ValueKey('digest-attention'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Notifications', style: theme.textTheme.titleMedium),
              SizedBox(height: tokens.spacing.xs),
              Text(
                status.detail ?? 'Notification access needs your attention.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: tokens.spacing.md),
              OutlinedButton(
                key: const ValueKey('digest-open-settings'),
                onPressed: entry.connector.openSystemSettings,
                child: const Text('Open settings'),
              ),
            ],
          ),
        ),
      );
    }
    if (!status.isConnected) return const SizedBox.shrink();

    final now = ref.watch(todayClockProvider)();
    final groups = digestGroups(
      ref.watch(notificationGroupsProvider).value ?? const [],
      now,
      readAt: ref.watch(notificationsReadAtProvider).value,
    );
    if (groups.isEmpty) return const SizedBox.shrink();
    final total = groups.fold<int>(0, (n, g) => n + g.items.length);
    final rows = groups.take(_maxRows).toList();
    return Padding(
      padding: EdgeInsets.only(top: tokens.spacing.lg),
      child: TodayCard(
        cardKey: const ValueKey('today-digest'),
        padding: EdgeInsets.fromLTRB(
          tokens.spacing.lg,
          tokens.spacing.md,
          tokens.spacing.sm,
          tokens.spacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$total ${total == 1 ? 'notification' : 'notifications'}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  key: const ValueKey('digest-mark-read'),
                  onPressed: () => ref
                      .read(notificationsReadAtProvider.notifier)
                      .markAllRead(),
                  child: const Text('Mark all read'),
                ),
              ],
            ),
            for (final g in rows)
              PressableScale(
                onTap: () => showNotificationSheet(context, g),
                semanticLabel: '${g.appLabel}, ${g.items.length}',
                child: Padding(
                  padding: EdgeInsets.only(
                    right: tokens.spacing.md,
                    top: tokens.spacing.xs,
                    bottom: tokens.spacing.xs,
                  ),
                  child: Row(
                    children: [
                      PersonAvatar(name: g.appLabel, size: 28, colorIndex: 1),
                      SizedBox(width: tokens.spacing.md),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: g.appLabel,
                                style: theme.textTheme.titleSmall,
                              ),
                              TextSpan(
                                text: '  ${_oneLineOf(g.items.first)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (g.items.length > 1)
                        Text(
                          '${g.items.length}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (groups.length > rows.length)
              Padding(
                padding: EdgeInsets.only(top: tokens.spacing.xs),
                child: Text(
                  'and ${groups.length - rows.length} more '
                  '${groups.length - rows.length == 1 ? 'app' : 'apps'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _oneLineOf(ConnectorItem i) =>
    oneLine(i.body.isNotEmpty ? i.body : i.title, 80);
