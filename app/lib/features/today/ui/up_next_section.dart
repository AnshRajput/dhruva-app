/// "Up next": the next two events with time range, "in 1h 48m", place and
/// attendees (names and photos from the contacts connector), a Prep action and
/// a tap-through to the event sheet. Hidden while the calendar is not
/// connected (the brief card carries the one connect action).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/connector_actions.dart';
import '../../../core/di/connector_providers.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../data/connectors/connector.dart';
import '../state/brief_facts.dart';
import '../state/day_text.dart';
import '../state/event_info.dart';
import '../state/today_data.dart';
import 'today_actions.dart';
import 'today_sheets.dart';
import 'today_widgets.dart';

class UpNextSection extends ConsumerWidget {
  const UpNextSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final loaded = ref.watch(connectorsLoadedProvider);
    final entry = ref.watch(calendarEntryProvider);
    final state = entry?.status.state;
    final shows =
        (entry?.status.isConnected ?? false) ||
        state == ConnectorState.needsAttention;
    if (loaded && !shows) {
      // Not connected (or access off): the brief card explains and fixes it.
      return const SizedBox.shrink();
    }
    final events = ref.watch(upNextEventsProvider);
    final shown = events.value;

    Widget body;
    if (!loaded || shown == null) {
      body = const _UpNextSkeleton();
    } else if (shown.isEmpty) {
      body = const _NothingNext();
    } else {
      body = _UpNextCard(events: shown);
    }
    final status = entry?.status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: tokens.spacing.lg),
        SectionHeader(
          title: 'Up next',
          actionLabel: 'See day',
          actionKey: const ValueKey('today-see-day'),
          onAction: () => context.push('/day'),
        ),
        SizedBox(height: tokens.spacing.sm),
        if (status?.state == ConnectorState.needsAttention &&
            status?.detail != null)
          _AttentionRow(status!.detail!),
        body,
        _SyncedCaption(lastSyncAt: status?.lastSyncAt),
        const _ContactsHint(),
      ],
    );
  }
}

class _UpNextSkeleton extends StatelessWidget {
  const _UpNextSkeleton();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    return Semantics(
      label: 'Loading your next events',
      child: TodayCard(
        cardKey: const ValueKey('up-next-skeleton'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonBar(width: 120, height: 12),
            SizedBox(height: tokens.spacing.md),
            const SkeletonBar(width: 200, height: 22),
            SizedBox(height: tokens.spacing.md),
            const SkeletonBar(width: 140, height: 12),
          ],
        ),
      ),
    );
  }
}

class _NothingNext extends ConsumerWidget {
  const _NothingNext();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return TodayCard(
      cardKey: const ValueKey('up-next-empty'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Nothing coming up', style: theme.textTheme.titleMedium),
          SizedBox(height: tokens.spacing.xs),
          Text(
            'Your calendar has no more events. Add one in your calendar app '
            'and it shows up here.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: tokens.spacing.md),
          OutlinedButton(
            key: const ValueKey('up-next-open-calendar'),
            onPressed: () => openCalendarWithFeedback(
              context,
              ref,
              ref.read(todayClockProvider)(),
            ),
            child: const Text('Open calendar'),
          ),
        ],
      ),
    );
  }
}

class _AttentionRow extends ConsumerWidget {
  const _AttentionRow(this.detail);
  final String detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 16, color: tokens.warning),
          SizedBox(width: tokens.spacing.sm),
          Expanded(
            child: Text(
              detail,
              key: const ValueKey('up-next-attention'),
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton(
            key: const ValueKey('up-next-retry'),
            onPressed: () => retryConnectorSync(context, ref),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

class _SyncedCaption extends StatelessWidget {
  const _SyncedCaption({required this.lastSyncAt});
  final DateTime? lastSyncAt;

  @override
  Widget build(BuildContext context) {
    final at = lastSyncAt;
    if (at == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Padding(
      padding: EdgeInsets.only(top: tokens.spacing.sm),
      child: Text(
        "Showing what's on this phone · last synced ${formatClock(context, at)}",
        key: const ValueKey('up-next-synced'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Offers Contacts (names and photos) once, only when it would show something.
class _ContactsHint extends ConsumerWidget {
  const _ContactsHint();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(contactsEntryProvider);
    final events = ref.watch(upNextEventsProvider).value ?? const [];
    final state = entry?.status.state;
    if (entry == null ||
        events.every((e) => e.people.isEmpty) ||
        state == ConnectorState.connected ||
        state == ConnectorState.syncing) {
      return const SizedBox.shrink();
    }
    final denied = state == ConnectorState.permissionDenied;
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Padding(
      padding: EdgeInsets.only(top: tokens.spacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              denied
                  ? 'Contacts access is off, so names and photos are missing.'
                  : 'Show names and photos next to meetings.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            key: const ValueKey('up-next-contacts'),
            onPressed: () async {
              final c = entry.connector;
              if (denied) {
                await ref
                    .read(connectorActionsProvider)
                    .openSystemSettings(c.id);
                return;
              }
              await c.connect();
              try {
                final hub = await ref.read(connectorHubProvider.future);
                await hub.sync.refresh();
              } on Object {
                // The status stream reports the failure.
              }
            },
            child: Text(denied ? 'Open settings' : 'Allow contacts'),
          ),
        ],
      ),
    );
  }
}

class _UpNextCard extends ConsumerWidget {
  const _UpNextCard({required this.events});
  final List<ConnectorItem> events;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;
    final now = ref.watch(nowProvider);
    final contacts = ref.watch(contactsDirectoryProvider).value ?? const {};
    final first = events.first;
    final people = attendeesOf(first, contacts);
    final place = placeLabel(first);
    final when = first.startsAt;
    return TodayCard(
      cardKey: const ValueKey('up-next-card'),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          PressableScale(
            onTap: () => showEventSheet(context, first),
            semanticLabel: '${first.title}, ${formatRange(context, first)}',
            child: Padding(
              padding: EdgeInsets.all(tokens.spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: tokens.spacing.sm,
                    runSpacing: tokens.spacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        formatRange(context, first),
                        style: theme.textTheme.titleMedium,
                      ),
                      if (when != null)
                        // Later days read "Tomorrow" / "Monday"; today reads
                        // "in 1h 48m" (timed events only).
                        if (!isAllDay(first))
                          InfoPill(
                            relativeStart(when, now),
                            pillKey: const ValueKey('up-next-relative'),
                          )
                        else if (dayLabel(when, now) case final day?)
                          InfoPill(
                            day,
                            pillKey: const ValueKey('up-next-relative'),
                          ),
                    ],
                  ),
                  SizedBox(height: tokens.spacing.xs),
                  Text(
                    first.title,
                    key: const ValueKey('up-next-title'),
                    style: theme.textTheme.headlineSmall,
                  ),
                  SizedBox(height: tokens.spacing.sm),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (people.isNotEmpty)
                              Row(
                                children: [
                                  AvatarStack(people: people, showOverflow: false),
                                  SizedBox(width: tokens.spacing.sm),
                                  Expanded(
                                    child: AttendeeLine(
                                      key: const ValueKey('up-next-people'),
                                      names: [for (final p in people) p.name],
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            if (place != null)
                              Padding(
                                padding: EdgeInsets.only(
                                  top: people.isEmpty ? 0 : tokens.spacing.xs,
                                ),
                                child: Text(
                                  place,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (canPrep(first)) ...[
                        SizedBox(width: tokens.spacing.sm),
                        FilledButton.tonalIcon(
                          key: const ValueKey('up-next-prep'),
                          icon: const Icon(
                            Icons.auto_awesome_outlined,
                            size: 18,
                          ),
                          label: const Text('Prep'),
                          onPressed: () => prepForEvent(context, first),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (events.length > 1) ...[
            Divider(
              height: 1,
              indent: tokens.spacing.lg,
              endIndent: tokens.spacing.lg,
            ),
            _SecondEvent(event: events[1], contacts: contacts, now: now),
          ],
        ],
      ),
    );
  }
}

class _SecondEvent extends StatelessWidget {
  const _SecondEvent({
    required this.event,
    required this.contacts,
    required this.now,
  });
  final ConnectorItem event;
  final Map<String, ConnectorItem> contacts;
  final DateTime now;

  /// "9:30 AM", or "Tomorrow 9:30 AM" / "Monday 9:30 AM" / "Tomorrow all day"
  /// when it is not today (Up next crosses midnight).
  String _timeText(BuildContext context, DateTime? start) {
    final day = start == null ? null : dayLabel(start, now);
    final time = isAllDay(event) || start == null
        ? 'All day'
        : formatClock(context, start);
    if (day == null) return time;
    return isAllDay(event) ? day : '$day $time';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;
    final place = placeLabel(event);
    final start = event.startsAt;
    return PressableScale(
      onTap: () => showEventSheet(context, event),
      semanticLabel: '${event.title}, ${formatRange(context, event)}',
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.lg,
          vertical: tokens.spacing.md,
        ),
        child: Row(
          children: [
            Text(
              _timeText(context, start),
              key: const ValueKey('up-next-second-time'),
              style: theme.textTheme.titleSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            SizedBox(width: tokens.spacing.base),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: event.title,
                      style: theme.textTheme.titleMedium,
                    ),
                    if (place != null)
                      TextSpan(
                        text: ' · $place',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(width: tokens.spacing.sm),
            AvatarStack(people: attendeesOf(event, contacts), max: 2, size: 28),
          ],
        ),
      ),
    );
  }
}
