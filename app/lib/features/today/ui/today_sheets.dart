/// Detail sheets opened from Today: one event (read-only; "Prep" and "Open in
/// calendar" are the actions) and one app's notifications. Everything shown
/// here is untrusted text from other people; it is only displayed, and the one
/// thing a tap can do with it is start a drafted reply the user then edits.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../data/connectors/connector.dart';
import '../../../data/connectors/connector_store.dart';
import '../state/brief_facts.dart';
import '../state/day_text.dart';
import '../state/event_info.dart';
import '../state/today_data.dart';
import 'today_actions.dart';
import 'today_widgets.dart';

Future<void> showEventSheet(BuildContext context, ConnectorItem event) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => EventSheet(event: event),
    );

class EventSheet extends ConsumerWidget {
  const EventSheet({super.key, required this.event});
  final ConnectorItem event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;
    final now = ref.watch(nowProvider);
    final contacts = ref.watch(contactsDirectoryProvider).value ?? const {};
    final people = attendeesOf(event, contacts);
    final place = placeLabel(event);
    final notes = eventNotes(event);
    final start = event.startsAt;
    final upcoming = start != null && start.isAfter(now);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        tokens.spacing.lg,
        0,
        tokens.spacing.lg,
        tokens.spacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  formatRange(context, event),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (upcoming && !isAllDay(event)) ...[
                SizedBox(width: tokens.spacing.sm),
                InfoPill(relativeStart(start, now)),
              ],
            ],
          ),
          SizedBox(height: tokens.spacing.sm),
          Text(
            event.title,
            key: const ValueKey('event-sheet-title'),
            style: theme.textTheme.headlineSmall,
          ),
          if (place != null) ...[
            SizedBox(height: tokens.spacing.sm),
            Row(
              children: [
                Icon(
                  meetingLabel(event) != null
                      ? Icons.link_outlined
                      : Icons.event_outlined,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                SizedBox(width: tokens.spacing.sm),
                Expanded(
                  child: Text(
                    place,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (people.isNotEmpty) ...[
            SizedBox(height: tokens.spacing.lg),
            Text('With', style: theme.textTheme.titleSmall),
            SizedBox(height: tokens.spacing.sm),
            for (final (i, p) in people.indexed)
              Padding(
                padding: EdgeInsets.only(bottom: tokens.spacing.sm),
                child: Row(
                  children: [
                    PersonAvatar(
                      name: p.name,
                      photoBase64: p.photoBase64,
                      colorIndex: i,
                    ),
                    SizedBox(width: tokens.spacing.md),
                    Expanded(
                      child: Text(p.name, style: theme.textTheme.bodyLarge),
                    ),
                  ],
                ),
              ),
          ],
          if (notes.isNotEmpty) ...[
            SizedBox(height: tokens.spacing.base),
            Text('Notes', style: theme.textTheme.titleSmall),
            SizedBox(height: tokens.spacing.xs),
            Text(
              notes,
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          SizedBox(height: tokens.spacing.xl),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('event-prep'),
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: const Text('Prep'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    prepForEvent(context, event);
                  },
                ),
              ),
              SizedBox(width: tokens.spacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('event-open-calendar'),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Open in calendar'),
                  onPressed: () => openInCalendar(context, ref, event),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> showNotificationSheet(
  BuildContext context,
  NotificationGroup group,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (_) => NotificationGroupSheet(group: group),
);

class NotificationGroupSheet extends ConsumerWidget {
  const NotificationGroupSheet({super.key, required this.group});
  final NotificationGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;
    final items = group.items.take(8).toList();
    final latest = items.first;
    final canReply = looksActionable(latest);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        tokens.spacing.lg,
        0,
        tokens.spacing.lg,
        tokens.spacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            group.appLabel,
            key: const ValueKey('notification-sheet-title'),
            style: theme.textTheme.headlineSmall,
          ),
          SizedBox(height: tokens.spacing.xs),
          Text(
            '${group.items.length} ${group.items.length == 1 ? 'notification' : 'notifications'} '
            'kept on this phone',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: tokens.spacing.base),
          for (final i in items)
            Padding(
              padding: EdgeInsets.only(bottom: tokens.spacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(i.title, style: theme.textTheme.titleSmall),
                        if (i.body.isNotEmpty)
                          Text(
                            i.body,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(width: tokens.spacing.md),
                  Text(
                    formatClock(context, i.sentAt ?? i.updatedAt),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          if (canReply) ...[
            SizedBox(height: tokens.spacing.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('notification-draft-reply'),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Draft reply'),
                onPressed: () {
                  final text = '${latest.title}: ${latest.body}';
                  Navigator.of(context).pop();
                  // Full-screen Actions route, prefilled; the user edits and
                  // sends it themselves.
                  context.push(
                    '/actions?id=draft_reply&text=${Uri.encodeQueryComponent(text)}',
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
