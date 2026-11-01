/// One notification in full (`/inbox/item/:id`): the original text, the
/// on-device summary when there is one, and four plain actions: Ask about
/// this (a new chat with this notification as its source), Open app (launch
/// the app it came from), Mark read / unread. Every action is a tap; nothing
/// in the notification text can trigger one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/connector_providers.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/failure_view.dart';
import '../../../core/widgets/platform_chrome.dart';
import '../../../data/connectors/connector.dart';
import '../state/inbox_grouping.dart';

class InboxItemScreen extends ConsumerWidget {
  const InboxItemScreen({super.key, required this.itemId});
  final int itemId;

  ConnectorItem? _find(List<ConnectorItem> all) {
    for (final i in all) {
      if (i.id == itemId) return i;
    }
    return null;
  }

  Future<void> _openApp(
    BuildContext context,
    WidgetRef ref,
    ConnectorItem item,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref
        .read(externalOpenerProvider)
        .launchApp(item.packageName);
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not open ${item.appLabel}. It may have been removed from '
            'this phone.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final items = ref.watch(inboxNotificationsProvider);

    final body = items.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorStateView(
        error: e,
        onRetry: () => ref.invalidate(inboxNotificationsProvider),
      ),
      data: (all) {
        final item = _find(all);
        if (item == null) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(tokens.spacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'This notification is no longer saved',
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: tokens.spacing.sm),
                  Text(
                    'Notifications are kept for 7 days.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  SizedBox(height: tokens.spacing.base),
                  FilledButton.tonal(
                    onPressed: () => context.pop(),
                    child: const Text('Back to Inbox'),
                  ),
                ],
              ),
            ),
          );
        }
        final store = ref.read(connectorStoreProvider);
        final when = MaterialLocalizations.of(
          context,
        ).formatTimeOfDay(TimeOfDay.fromDateTime(item.when));
        final summary = item.summary;
        return ListView(
          padding: EdgeInsets.all(tokens.spacing.base),
          children: [
            Semantics(
              header: true,
              child: Text(item.title, style: theme.textTheme.headlineSmall),
            ),
            SizedBox(height: tokens.spacing.xs),
            Text(
              '${item.appLabel} · ${inboxWhen(item.when, DateTime.now(), (_) => when)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (summary != null && summary.isNotEmpty) ...[
              SizedBox(height: tokens.spacing.base),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(tokens.radius.lg),
                ),
                child: Padding(
                  padding: EdgeInsets.all(tokens.spacing.base),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Summary, written on this phone',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      SizedBox(height: tokens.spacing.xs),
                      Text(
                        summary,
                        key: const ValueKey('inbox-detail-summary'),
                        style: theme.textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            SizedBox(height: tokens.spacing.base),
            Text(
              'Original',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            SizedBox(height: tokens.spacing.xs),
            SelectableText(
              item.body.isEmpty ? '(No text)' : item.body,
              key: const ValueKey('inbox-detail-text'),
              style: theme.textTheme.bodyLarge,
            ),
            SizedBox(height: tokens.spacing.xl),
            Wrap(
              spacing: tokens.spacing.sm,
              runSpacing: tokens.spacing.sm,
              children: [
                FilledButton(
                  key: const ValueKey('inbox-ask'),
                  onPressed: () => context.push('/chat/new?source=${item.id}'),
                  child: const Text('Ask about this'),
                ),
                OutlinedButton(
                  key: const ValueKey('inbox-open-app'),
                  onPressed: item.packageName.isEmpty
                      ? null
                      : () => _openApp(context, ref, item),
                  child: const Text('Open app'),
                ),
                OutlinedButton(
                  key: const ValueKey('inbox-mark-read'),
                  onPressed: () => store.setItemFlag(
                    item.id,
                    'read',
                    item.isRead ? null : true,
                  ),
                  child: Text(item.isRead ? 'Mark unread' : 'Mark read'),
                ),
              ],
            ),
          ],
        );
      },
    );

    return ChromeScaffold(
      appBar: const AdaptiveAppBar(title: Text('Notification')),
      bodyBuilder: (context, inset) => Padding(
        padding: EdgeInsets.only(top: inset.top, bottom: inset.bottom),
        child: body,
      ),
    );
  }
}
