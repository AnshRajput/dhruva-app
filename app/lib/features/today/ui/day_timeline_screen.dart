/// "See day" (`/day`): direction B's timeline. Today's events on a vertical
/// rail with notification groups slotted at their time and a "now" marker.
/// Empty day, calendar off and loading each have their own state.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/next_step_card.dart';
import '../../../core/widgets/platform_chrome.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../data/connectors/connector.dart';
import '../state/brief_facts.dart';
import '../state/day_text.dart';
import '../state/day_timeline.dart';
import '../state/event_info.dart';
import '../state/today_data.dart';
import 'today_actions.dart';
import 'today_sheets.dart';
import 'today_widgets.dart';

class DayTimelineScreen extends ConsumerWidget {
  const DayTimelineScreen({super.key, this.now});

  /// Test seam for the date and the "now" marker.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    final clock =
        now ??
        ref.watch(minuteTickProvider).value ??
        ref.watch(todayClockProvider)();
    final loaded = ref.watch(connectorsLoadedProvider);
    final calendar = ref.watch(calendarEntryProvider);
    final events = ref.watch(todayEventsProvider);
    // Same read-state source as Today and the brief: "Mark all read" hides
    // notifications here too.
    final groups = ref.watch(unreadNotificationGroupsProvider);

    Widget body(BuildContext context, EdgeInsets inset) {
      if (!loaded || events.isLoading && !events.hasValue) {
        return _TimelineSkeleton(inset: inset);
      } else {
        final entries = buildTimeline(
          now: clock,
          events: events.value ?? const [],
          groups: groups,
        );
        final calendarOn = calendar?.status.isConnected ?? false;
        if (timelineIsEmpty(entries)) {
          return ListView(
            padding: EdgeInsets.all(tokens.spacing.base).add(inset),
            children: [
              if (!calendarOn)
                NextStepCard(
                  icon: Icons.timeline_rounded,
                  title: 'Nothing on your day yet',
                  body:
                      'Meetings from your calendar show up here as a timeline, '
                      'with your notifications in between. It needs no sign-in '
                      'and never leaves this phone.',
                  actionLabel: 'Connect your calendar',
                  actionKey: const ValueKey('day-connect-calendar'),
                  onAction: () async {
                    final status = await connectCalendar(ref);
                    if (!context.mounted) return;
                    if (status == null || !status.isConnected) {
                      unawaited(context.push('/settings/connectors'));
                    }
                  },
                )
              else
                NextStepCard(
                  icon: Icons.timeline_rounded,
                  title: 'A clear day',
                  body:
                      'Nothing on your calendar today. Add something in your '
                      'calendar app and it shows up here.',
                  actionLabel: 'Open calendar',
                  actionKey: const ValueKey('day-open-calendar'),
                  onAction: () => openCalendarWithFeedback(context, ref, clock),
                ),
            ],
          );
        } else {
          return ListView(
            padding: EdgeInsets.fromLTRB(
              tokens.spacing.base,
              tokens.spacing.sm,
              tokens.spacing.base,
              tokens.spacing.xl2,
            ).add(inset),
            children: [
              for (final (i, e) in entries.indexed)
                _RailRow(
                  key: ValueKey('timeline-$i'),
                  entry: e,
                  first: i == 0,
                  last: i == entries.length - 1,
                ),
            ],
          );
        }
      }
    }

    return ChromeScaffold(
      appBar: AdaptiveAppBar(title: Text(formatDayLine(clock))),
      bodyBuilder: body,
    );
  }
}

class _TimelineSkeleton extends StatelessWidget {
  const _TimelineSkeleton({required this.inset});
  final EdgeInsets inset;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    return Semantics(
      label: 'Loading your day',
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.base).add(inset),
        child: Column(
          children: [
            for (var i = 0; i < 3; i++) ...[
              TodayCard(
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBar(width: 60, height: 12),
                    SizedBox(height: 12),
                    SkeletonBar(width: 180, height: 20),
                  ],
                ),
              ),
              SizedBox(height: tokens.spacing.md),
            ],
          ],
        ),
      ),
    );
  }
}

class _RailRow extends StatelessWidget {
  const _RailRow({
    super.key,
    required this.entry,
    required this.first,
    required this.last,
  });

  final TimelineEntry entry;
  final bool first;
  final bool last;

  /// Where the dot's centre sits from the row's top (4 padding + half of the
  /// 12 px dot).
  static const _dotCenter = 10.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;
    final e = entry;
    final isNow = e is NowEntry;
    final timeText = formatClock(context, e.at);
    final subText = e is EventEntry && e.event.startsAt != null
        ? _duration(e.event)
        : null;

    final dot = switch (e) {
      NowEntry() => Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: scheme.primary.withValues(alpha: 0.4),
            width: 3,
          ),
          color: scheme.primary,
        ),
      ),
      EventEntry() => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: e.isPast ? scheme.outline : scheme.onSurfaceVariant,
        ),
      ),
      NotificationEntry() => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: scheme.primary, width: 2),
        ),
      ),
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 64,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isNow ? 'Now' : timeText,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: isNow ? scheme.primary : null,
                    ),
                  ),
                  if (subText != null)
                    Text(
                      subText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 24,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                // One continuous rail: the first row starts at its dot, every
                // row but the last runs to its bottom edge, and the last stops
                // at its dot.
                if (!(first && last))
                  Positioned(
                    top: first ? _dotCenter : 0,
                    bottom: last ? null : 0,
                    height: last ? _dotCenter : null,
                    child: Container(
                      key: const ValueKey('timeline-rail'),
                      width: 2,
                      color: scheme.outlineVariant,
                    ),
                  ),
                Padding(padding: const EdgeInsets.only(top: 4), child: dot),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: tokens.spacing.md),
              child: switch (e) {
                NowEntry() => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    e.caption,
                    key: const ValueKey('timeline-now-caption'),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                EventEntry() => _EventCard(entry: e),
                NotificationEntry() => _NotificationCard(entry: e),
              },
            ),
          ),
        ],
      ),
    );
  }

  String? _duration(ConnectorItem ev) {
    final end = eventEnd(ev);
    final start = ev.startsAt;
    if (end == null || start == null || isAllDay(ev)) return null;
    return durationLabel(end.difference(start));
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.entry});
  final EventEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;
    final ev = entry.event;
    final place = placeLabel(ev);
    return Opacity(
      opacity: entry.isPast ? 0.6 : 1,
      child: PressableScale(
        onTap: () => showEventSheet(context, ev),
        semanticLabel: '${ev.title}, ${formatRange(context, ev)}',
        child: TodayCard(
          padding: EdgeInsets.all(tokens.spacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ev.title, style: theme.textTheme.titleLarge),
              if (entry.overlapsWith != null) ...[
                SizedBox(height: tokens.spacing.xs),
                Row(
                  key: ValueKey('timeline-overlap-${ev.id}'),
                  children: [
                    Icon(Icons.warning_amber, size: 16, color: tokens.warning),
                    SizedBox(width: tokens.spacing.xs),
                    Expanded(
                      child: Text(
                        'Overlaps ${entry.overlapsWith}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (place != null) ...[
                SizedBox(height: tokens.spacing.xs),
                Text(
                  place,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (!entry.isPast) ...[
                SizedBox(height: tokens.spacing.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    key: ValueKey('timeline-prep-${ev.id}'),
                    icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: const Text('Prep'),
                    onPressed: () => prepForEvent(context, ev),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.entry});
  final NotificationEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;
    final g = entry.group;
    final latest = entry.items.first;
    return PressableScale(
      onTap: () => showNotificationSheet(context, g),
      semanticLabel: '${g.appLabel}, ${entry.items.length} notifications today',
      child: TodayCard(
        padding: EdgeInsets.all(tokens.spacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PersonAvatar(
              name: entry.actionable ? latest.title : g.appLabel,
              size: 36,
              colorIndex: entry.actionable ? 0 : 1,
            ),
            SizedBox(width: tokens.spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: entry.actionable ? latest.title : g.appLabel,
                          style: theme.textTheme.titleSmall,
                        ),
                        if (entry.actionable)
                          TextSpan(
                            text: '  ${g.appLabel}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    entry.actionable
                        ? latest.body
                        : '${entry.items.length} '
                              '${entry.items.length == 1 ? 'notification' : 'notifications'}'
                              ' · ${oneLine(latest.body.isEmpty ? latest.title : latest.body, 60)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (entry.actionable)
                    Padding(
                      padding: EdgeInsets.only(top: tokens.spacing.xs),
                      child: Text(
                        'Needs reply',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
