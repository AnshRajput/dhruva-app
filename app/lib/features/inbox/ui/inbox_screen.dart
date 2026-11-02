/// Inbox: notifications (Android) in one calm list, matching the approved
/// inbox comp: filter chips (All, then one per app), sections Today / Earlier,
/// rows with an app avatar, the notification title, a one-line summary and the
/// time. Mail rows join with Gmail in 0.7b.
///
/// Summaries are written on the phone, lazily, only for the rows built on
/// screen while the app is in the foreground (`InboxSummarizer`); until one is
/// ready the row shows the notification's own text.
///
/// States: skeleton while loading, "set up" when no inbox source is connected,
/// access-off with an Open settings fix, connected but empty, a failure with a
/// retry. Also reachable full-screen at `/inbox/connect` (back button shown).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/connector_actions.dart';
import '../../../core/di/connector_providers.dart';
import '../../../core/format/when.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/failure_view.dart';
import '../../../core/widgets/next_step_card.dart';
import '../../../core/widgets/platform_chrome.dart';
import '../../../data/connectors/connector.dart';
import '../state/inbox_grouping.dart';
import '../state/inbox_summarizer.dart';

class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key, this.standalone = false});

  /// True when shown as a full-screen route (not the shell tab).
  final bool standalone;

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  /// Package of the app chip that is selected; null is "All".
  String? _filter;

  @override
  void initState() {
    super.initState();
    // Opening the Inbox shows what arrived since the last look: the queue is
    // drained now, not at the next 10-minute sync.
    Future.microtask(() {
      if (mounted) {
        unawaited(ref.read(connectorActionsProvider).drainNotifications());
      }
    });
  }

  Future<void> _openItem(ConnectorItem item) async {
    // The detail (and a chat opened from it) needs the engine: stop writing
    // summaries until the user is back on the list.
    final summarizer = ref.read(inboxSummarizerProvider);
    summarizer.pause();
    try {
      await context.push('/inbox/item/${item.id}');
    } finally {
      summarizer.resume();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    final list = ref.watch(connectorListProvider).value;
    final notifications = list
        ?.where((e) => e.connector.id == ConnectorIds.notifications)
        .firstOrNull;
    final connected = notifications?.status.isConnected ?? false;
    final needsFix =
        notifications != null &&
        (notifications.status.state == ConnectorState.needsAttention ||
            notifications.status.state == ConnectorState.permissionDenied);

    // The tab only exists once an inbox source is connected, so the list is
    // loaded by the time anyone sees it; the set-up route and a deep link can
    // arrive first, and for them "set up" is the honest answer meanwhile.
    Widget body;
    if (!connected && !needsFix) {
      body = _Padded(
        child: NextStepCard(
          icon: Icons.inbox_outlined,
          title: 'Your inbox, in one calm list',
          body:
              'Connect mail or, on Android, the notification digest. Each row '
              'gets a one-line summary written on this phone. Nothing leaves '
              'this phone.',
          actionLabel: 'Connect an inbox source',
          actionKey: const ValueKey('inbox-connect'),
          onAction: () => context.push('/settings/connectors'),
        ),
      );
    } else {
      final items = ref.watch(inboxNotificationsProvider);
      body = items.when(
        loading: () => const _InboxSkeleton(),
        error: (e, _) => ErrorStateView(
          error: e,
          onRetry: () => ref.invalidate(inboxNotificationsProvider),
        ),
        data: (all) {
          if (all.isEmpty) {
            return _Padded(
              child: Column(
                children: [
                  if (needsFix) _AccessBanner(entry: notifications),
                  NextStepCard(
                    icon: Icons.notifications_none,
                    title: 'Nothing here yet',
                    body:
                        'Notifications from your apps show up here as they '
                        'arrive, newest first. Apps you skip are never saved.',
                    actionLabel: 'Choose apps to skip',
                    actionKey: const ValueKey('inbox-empty-action'),
                    onAction: () => context.push('/settings/connectors'),
                  ),
                ],
              ),
            );
          }
          return _InboxList(
            items: all,
            filter: _filter,
            onFilter: (p) => setState(() => _filter = p),
            onOpen: _openItem,
            banner: needsFix ? _AccessBanner(entry: notifications) : null,
          );
        },
      );
    }

    return ChromeScaffold(
      appBar: AdaptiveAppBar(
        title: const Text('Inbox'),
        automaticallyImplyLeading: widget.standalone,
      ),
      bodyBuilder: (context, inset) => Padding(
        padding: EdgeInsets.only(
          top: inset.top + tokens.spacing.xs,
          bottom: inset.bottom,
        ),
        child: RefreshIndicator(
          onRefresh: ref.read(connectorActionsProvider).refreshAll,
          child: body,
        ),
      ),
    );
  }
}

class _Padded extends StatelessWidget {
  const _Padded({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.all(tokens.spacing.base),
      children: [child],
    );
  }
}

class _AccessBanner extends ConsumerWidget {
  const _AccessBanner({required this.entry});
  final ConnectorEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.spacing.md),
      child: DecoratedBox(
        key: const ValueKey('inbox-access-off'),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(tokens.radius.lg),
          border: Border.all(color: tokens.warning, width: 1.5),
        ),
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Notification access is off',
                style: theme.textTheme.titleMedium,
              ),
              SizedBox(height: tokens.spacing.xs),
              Text(
                entry.status.detail ??
                    'Turn access back on to keep this list fresh. What is '
                        'already saved stays here.',
                style: theme.textTheme.bodyMedium,
              ),
              SizedBox(height: tokens.spacing.md),
              FilledButton(
                key: const ValueKey('inbox-open-settings'),
                onPressed: () => ref
                    .read(connectorActionsProvider)
                    .openSystemSettings(ConnectorIds.notifications),
                child: const Text('Open settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- list -----------------------------------------------------------------------

sealed class _Entry {}

final class _Header extends _Entry {
  _Header(this.title, this.count);
  final String title;
  final int count;
}

final class _Row extends _Entry {
  _Row(this.item);
  final ConnectorItem item;
}

class _InboxList extends StatelessWidget {
  const _InboxList({
    required this.items,
    required this.filter,
    required this.onFilter,
    required this.onOpen,
    this.banner,
  });
  final List<ConnectorItem> items;
  final String? filter;
  final ValueChanged<String?> onFilter;
  final ValueChanged<ConnectorItem> onOpen;
  final Widget? banner;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    final filters = appFilters(items);
    // A filter whose app has no notifications left falls back to All.
    final active = filters.any((f) => f.package == filter) ? filter : null;
    final sections = groupInbox(items, DateTime.now(), filterPackage: active);
    final entries = <_Entry>[
      for (final s in sections) ...[
        _Header(s.title, s.items.length),
        for (final i in s.items) _Row(i),
      ],
    ];
    return Column(
      children: [
        if (banner != null)
          Padding(
            padding: EdgeInsets.fromLTRB(
              tokens.spacing.base,
              tokens.spacing.sm,
              tokens.spacing.base,
              0,
            ),
            child: banner,
          ),
        if (filters.length > 1)
          _FilterBar(
            filters: filters,
            total: items.length,
            active: active,
            onChanged: onFilter,
          ),
        Expanded(
          child: ListView.builder(
            // Rows built = rows on screen: the lazy summaries follow this.
            cacheExtent: 0,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              tokens.spacing.base,
              0,
              tokens.spacing.base,
              tokens.spacing.xl2,
            ),
            itemCount: entries.length,
            itemBuilder: (context, i) => switch (entries[i]) {
              _Header(:final title, :final count) => _SectionHeader(
                title: title,
                count: count,
              ),
              _Row(:final item) => InboxRowTile(
                key: ValueKey('inbox-row-${item.id}'),
                item: item,
                onTap: () => onOpen(item),
              ),
            },
          ),
        ),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filters,
    required this.total,
    required this.active,
    required this.onChanged,
  });
  final List<AppFilter> filters;
  final int total;
  final String? active;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.base,
          vertical: tokens.spacing.sm,
        ),
        children: [
          Padding(
            padding: EdgeInsets.only(right: tokens.spacing.sm),
            child: ChoiceChip(
              key: const ValueKey('inbox-filter-all'),
              label: const Text('All'),
              selected: active == null,
              onSelected: (_) => onChanged(null),
            ),
          ),
          for (final f in filters)
            Padding(
              padding: EdgeInsets.only(right: tokens.spacing.sm),
              child: ChoiceChip(
                key: ValueKey('inbox-filter-${f.package}'),
                label: Text('${f.label} ${f.count}'),
                selected: active == f.package,
                onSelected: (_) => onChanged(f.package),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Padding(
      padding: EdgeInsets.only(
        top: tokens.spacing.base,
        bottom: tokens.spacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: theme.textTheme.titleLarge),
            ),
          ),
          Text(
            '$count',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One notification. While it is built (on screen) it asks the summarizer for
/// its one-line summary; when it goes away it withdraws the request.
class InboxRowTile extends ConsumerStatefulWidget {
  const InboxRowTile({super.key, required this.item, required this.onTap});
  final ConnectorItem item;
  final VoidCallback onTap;

  @override
  ConsumerState<InboxRowTile> createState() => _InboxRowTileState();
}

class _InboxRowTileState extends ConsumerState<InboxRowTile> {
  late final InboxSummarizer _summarizer;

  @override
  void initState() {
    super.initState();
    _summarizer = ref.read(inboxSummarizerProvider);
    // After the frame: never start work in the middle of building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _summarizer.request(widget.item);
    });
  }

  @override
  void dispose() {
    _summarizer.cancel(widget.item.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final item = widget.item;
    final scheme = theme.colorScheme;
    final tints = [
      scheme.primaryContainer,
      scheme.secondaryContainer,
      scheme.tertiaryContainer,
    ];
    final tint = tints[item.packageName.hashCode.abs() % tints.length];
    final summary = item.summary;
    final line = (summary != null && summary.isNotEmpty)
        ? summary
        : item.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    final when = shortWhen(
      item.when,
      DateTime.now(),
      (d) => MaterialLocalizations.of(
        context,
      ).formatTimeOfDay(TimeOfDay.fromDateTime(d)),
    );
    return InkWell(
      onTap: widget.onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: tokens.spacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: CircleAvatar(
                radius: 22,
                backgroundColor: tint,
                child: Text(
                  avatarLetters(item.appLabel),
                  style: theme.textTheme.labelLarge,
                ),
              ),
            ),
            SizedBox(width: tokens.spacing.md),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  // Wide: the app chip sits beside the title (as in the comp).
                  // On a phone-width column the title keeps the whole line and
                  // the chip drops below it, so a long app name never crushes it.
                  final narrow = box.maxWidth < 300;
                  final chip = _AppChip(label: item.appLabel);
                  final title = Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: item.isRead
                          ? FontWeight.w400
                          : FontWeight.w700,
                    ),
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (narrow)
                        title
                      else
                        Row(
                          children: [
                            Flexible(child: title),
                            SizedBox(width: tokens.spacing.sm),
                            chip,
                          ],
                        ),
                      if (line.isNotEmpty) ...[
                        SizedBox(height: tokens.spacing.xs),
                        Text(
                          line,
                          key: ValueKey('inbox-line-${item.id}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (narrow) ...[
                        SizedBox(height: tokens.spacing.xs),
                        chip,
                      ],
                    ],
                  );
                },
              ),
            ),
            SizedBox(width: tokens.spacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  when,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (!item.isRead) ...[
                  SizedBox(height: tokens.spacing.xs),
                  Semantics(
                    label: 'Unread',
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InboxSkeleton extends StatelessWidget {
  const _InboxSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    Widget bar(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(tokens.radius.sm),
      ),
    );
    return Semantics(
      label: 'Loading inbox',
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.base),
        child: Column(
          children: [
            for (var i = 0; i < 4; i++)
              Padding(
                padding: EdgeInsets.symmetric(vertical: tokens.spacing.md),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: tokens.spacing.md),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        bar(160, 14),
                        SizedBox(height: tokens.spacing.sm),
                        bar(240, 12),
                      ],
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

/// The app-name pill. Capped so a very long app name ellipsises instead of
/// overflowing its row.
class _AppChip extends StatelessWidget {
  const _AppChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 160),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(tokens.radius.full),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spacing.sm,
            vertical: tokens.spacing.xs / 2,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall,
          ),
        ),
      ),
    );
  }
}
