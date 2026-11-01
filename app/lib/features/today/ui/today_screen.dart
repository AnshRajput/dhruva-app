/// Today (`/today`): the daily-assistant home, direction A ("calm brief") from
/// the approved comps, with B's timeline behind "See day".
///
/// Real data from the Wave 2A connectors: a greeting with the name from About
/// me, the date and a one-line day summary, the brief (a fact list that the
/// on-device model words, every phrase citing a fact), Up next, Needs you, and
/// on Android the notification digest. Pull to refresh re-syncs and rewrites
/// the brief. The brief is only ever written while the app is open.
///
/// All navigation from here pushes FULL-SCREEN routes only (`/settings`,
/// `/actions`, `/day`, `/chat/new`, ...), never a shell-branch route.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/crash/crash_banner.dart';
import '../../../core/di/connector_actions.dart';
import '../../../core/di/connector_providers.dart';
import '../../../core/identity/app_identity.dart';
import '../../../core/router/inbox_availability.dart';
import '../../../core/theme/brand_star.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/update/shorebird_update_banner.dart';
import '../../../core/update/shorebird_update_service.dart';
import '../../../core/widgets/next_step_card.dart';
import '../../../core/widgets/platform_chrome.dart';
import '../../../data/connectors/connector.dart';
import '../state/brief_controller.dart';
import '../state/brief_facts.dart';
import '../state/brief_writer.dart';
import '../state/day_text.dart';
import '../state/today_data.dart';
import 'brief_card.dart';
import 'notification_sections.dart';
import 'quick_actions.dart';
import 'up_next_section.dart';

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key, this.statusPill, this.now});

  /// Optional download status pill, injected by the composition root so
  /// `features/today` never imports `features/models_hub` (ADR-002).
  final Widget? statusPill;

  /// Test seam for the greeting/date.
  final DateTime? now;

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onOpen());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Back from system settings, say: re-read what the OS now allows first, so
    // a Calendar grant turns the card into the real day.
    unawaited(resumeConnectors(ref).whenComplete(_onOpen));
  }

  /// Write a new brief only if the cached one is stale (see BriefController).
  void _onOpen() {
    if (!mounted) return;
    // Foreground only: data arriving while the app is in the background never
    // starts a model.
    final life = WidgetsBinding.instance.lifecycleState;
    if (life != null && life != AppLifecycleState.resumed) return;
    unawaited(ref.read(briefControllerProvider.notifier).onOpen());
  }

  Future<void> _refresh() async {
    try {
      final hub = await ref.read(connectorHubProvider.future);
      await hub.sync.refresh();
    } on Object {
      // Each connector shows its own failure; the brief can still be rewritten.
    }
    if (!mounted) return;
    final brief = ref.read(briefControllerProvider.notifier);
    if (ref.read(briefFactsProvider).isNotEmpty) {
      // Not awaited: the spinner is for the sync; the card shows "Writing…".
      unawaited(brief.regenerate());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final DateTime today = widget.now ?? ref.watch(nowProvider);
    final scheme = theme.colorScheme;
    final name = ref.watch(todayNameProvider);
    final summary = ref.watch(daySummaryProvider);

    // Disconnecting a source removes whatever was written from it.
    ref.listen(connectorListProvider, (_, next) {
      final list = next.value;
      if (list == null) return;
      bool on(String id) =>
          list.any((e) => e.connector.id == id && e.status.isConnected);
      unawaited(
        ref
            .read(briefControllerProvider.notifier)
            .forgetDisconnected(
              calendarConnected: on(ConnectorIds.calendar),
              notificationsConnected: on(ConnectorIds.notifications),
            ),
      );
    });
    // First facts arrive (calendar just connected) or a model just landed:
    // write the brief if it is due.
    // Also when the sources change under a shown brief (a meeting appears
    // after the first sync): the controller drops it and writes a new one.
    ref.listen(briefFactsProvider, (prev, next) {
      if (next.isNotEmpty && !sameFactSources(prev ?? const [], next)) {
        _onOpen();
      }
    });
    ref.listen(briefControllerProvider.select((s) => s.value?.model), (
      prev,
      next,
    ) {
      if (prev == BriefModelStatus.none &&
          next != null &&
          next != BriefModelStatus.none) {
        _onOpen();
      }
    });

    final warming = ref.watch(
      briefControllerProvider.select((s) => s.value?.warming ?? false),
    );
    final inboxAvailable = ref.watch(inboxAvailableProvider);
    final loaded = ref.watch(connectorsLoadedProvider);
    final waiting = needsYou(
      ref.watch(notificationGroupsProvider).value ?? const [],
      today,
    );

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
      bodyBuilder: (context, inset) => RefreshIndicator(
        onRefresh: _refresh,
        edgeOffset: inset.top,
        child: ListView(
          key: const ValueKey('today-list'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            top: inset.top + tokens.spacing.xs,
            bottom: inset.bottom + tokens.spacing.xl2,
          ),
          children: [
            // Update / crash nudges used to sit on the Chats home; Today is home now.
            const _SystemBanners(),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: tokens.spacing.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    greetingWithName(today, name),
                    key: const ValueKey('today-greeting'),
                    style: theme.textTheme.headlineMedium,
                  ),
                  SizedBox(height: tokens.spacing.xs),
                  Text(
                    summary.isEmpty
                        ? formatDayLine(today)
                        : '${formatDayLine(today)} · $summary',
                    key: const ValueKey('today-date-line'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (widget.statusPill != null || warming) ...[
                    SizedBox(height: tokens.spacing.sm),
                    Wrap(
                      spacing: tokens.spacing.sm,
                      children: [
                        if (widget.statusPill != null) widget.statusPill!,
                        if (warming)
                          const Chip(
                            key: ValueKey('model-warming-pill'),
                            avatar: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            label: Text('Warming up your model'),
                          ),
                      ],
                    ),
                  ],
                  SizedBox(height: tokens.spacing.base),
                  const BriefCard(),
                  SizedBox(height: tokens.spacing.base),
                  const QuickActionsRow(),
                  const UpNextSection(),
                  const NeedsYouSection(),
                  const DigestCard(),
                  if (loaded && !inboxAvailable && waiting.isEmpty) ...[
                    SizedBox(height: tokens.spacing.lg),
                    NextStepCard(
                      icon: Icons.inbox_outlined,
                      title: 'Set up your inbox',
                      body:
                          'Messages that need a reply, in one calm list with a '
                          'drafted answer you edit and send yourself.',
                      actionLabel: 'Set up inbox',
                      actionKey: const ValueKey('today-setup-inbox'),
                      // Full-screen route, NOT the shell's /inbox branch.
                      onAction: () => context.push('/inbox/connect'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The code-push update nudge and the crash-report nudge, formerly shown on the
/// Chats home. Watching the update provider here also starts the manual
/// code-push check at launch (Ask, a lazily-built tab, used to do that).
class _SystemBanners extends ConsumerWidget {
  const _SystemBanners();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(shorebirdUpdateProvider);
    return const Column(
      children: [ShorebirdUpdateBanner(), CrashReportBanner()],
    );
  }
}
