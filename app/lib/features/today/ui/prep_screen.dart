/// Meeting prep (`/prep/:id`): a card built by rules from what is on the phone
/// (see `prep_data.dart`), not written by a model. Time and place, who is in
/// it and what is known of them, related notes and files, and recent
/// notifications from the people; each row opens its source. "Ask a
/// follow-up" is the optional model step and goes through `/ask/new`.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/connector_actions.dart';
import '../../../core/format/when.dart';
import '../../../core/router/ask_route.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/failure_view.dart';
import '../../../core/widgets/platform_chrome.dart';
import '../../../data/connectors/ask_sources.dart';
import '../../../data/connectors/connector.dart';
import '../state/event_info.dart';
import '../state/prep_data.dart';
import '../state/today_data.dart';
import 'today_actions.dart';
import 'today_sheets.dart';
import 'today_widgets.dart';

class PrepScreen extends ConsumerWidget {
  const PrepScreen({super.key, required this.eventId});
  final int eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prep = ref.watch(prepProvider(eventId));
    return ChromeScaffold(
      appBar: const AdaptiveAppBar(title: Text('Prep')),
      bodyBuilder: (context, inset) => Padding(
        padding: EdgeInsets.only(top: inset.top, bottom: inset.bottom),
        child: prep.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorStateView(
            error: e,
            onRetry: () => ref.invalidate(prepProvider(eventId)),
          ),
          data: (data) => data == null ? const _Gone() : _PrepBody(data: data),
        ),
      ),
    );
  }
}

class _Gone extends StatelessWidget {
  const _Gone();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'That event is no longer on your calendar',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: tokens.spacing.base),
            FilledButton.tonal(
              onPressed: () => context.pop(),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrepBody extends ConsumerWidget {
  const _PrepBody({required this.data});
  final PrepData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;
    final event = data.event;
    final place = placeLabel(event);
    final notes = eventNotes(event);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    // "Not in your contacts" is only true when Contacts is connected; until
    // the connector list loads we say nothing rather than guess.
    final contactsLoaded = ref.watch(connectorsLoadedProvider);
    final contactsOn =
        ref.watch(contactsEntryProvider)?.status.isConnected ?? false;
    return ListView(
      key: const ValueKey('prep-card'),
      padding: EdgeInsets.fromLTRB(
        tokens.spacing.base,
        tokens.spacing.sm,
        tokens.spacing.base,
        tokens.spacing.xl2,
      ),
      children: [
        Text(
          formatRange(context, event),
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        SizedBox(height: tokens.spacing.xs),
        Semantics(
          header: true,
          child: Text(
            event.title,
            key: const ValueKey('prep-title'),
            style: theme.textTheme.headlineSmall,
          ),
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
              Expanded(child: Text(place, style: muted)),
            ],
          ),
        ],
        if (notes.isNotEmpty) ...[
          SizedBox(height: tokens.spacing.sm),
          Text(
            notes,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: muted,
          ),
        ],
        SizedBox(height: tokens.spacing.lg),
        SectionHeader(title: 'Who is in it'),
        SizedBox(height: tokens.spacing.xs),
        if (data.people.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: tokens.spacing.sm),
            child: Text(
              'No attendees on this event. It looks like a solo block.',
              style: muted,
            ),
          )
        else
          for (final (i, p) in data.people.indexed)
            _PersonRow(
              key: ValueKey('prep-person-$i'),
              person: p,
              contactsOn: contactsOn,
              colorIndex: i,
              onTap: () =>
                  unawaited(context.push(prepPersonAskLocation(p, event.id))),
              onOpenMeeting: (m) => unawaited(showEventSheet(context, m)),
            ),
        if (contactsLoaded && !contactsOn && data.people.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('prep-connect-contacts'),
              onPressed: () async {
                final status = await connectAndSync(ref, ConnectorIds.contacts);
                if (!context.mounted) return;
                if (status == null || !status.isConnected) {
                  unawaited(context.push('/settings/connectors'));
                }
              },
              child: const Text("Connect contacts to see who's who"),
            ),
          ),
        if (data.files.isNotEmpty) ...[
          SizedBox(height: tokens.spacing.lg),
          SectionHeader(title: 'Notes and files'),
          for (final f in data.files)
            _SourceRow(
              key: ValueKey('prep-file-${f.id}'),
              icon: Icons.description_outlined,
              title: f.title.isEmpty ? 'Untitled' : f.title,
              subtitle: 'Possibly related',
              onTap: () =>
                  unawaited(context.push(askNewLocation(focus: [f.id]))),
            ),
        ],
        if (data.notifications.isNotEmpty) ...[
          SizedBox(height: tokens.spacing.lg),
          SectionHeader(title: 'Recent from them'),
          for (final n in data.notifications)
            _SourceRow(
              key: ValueKey('prep-notification-${n.id}'),
              icon: Icons.notifications_none,
              title: n.title.isEmpty ? 'Notification' : n.title,
              subtitle: _firstLine(n.body),
              trailing: shortWhen(
                n.sentAt ?? n.updatedAt,
                ref.read(todayClockProvider)(),
                (d) => formatClock(context, d),
              ),
              onTap: () => unawaited(context.push('/inbox/item/${n.id}')),
            ),
        ],
        if (!data.hasRelated) ...[
          SizedBox(height: tokens.spacing.lg),
          Text(
            key: const ValueKey('prep-nothing-else'),
            'Nothing else on this phone mentions this meeting or the people '
            'in it yet. Notes in your folder and recent notifications show up '
            'here.',
            style: muted,
          ),
        ],
        SizedBox(height: tokens.spacing.xl),
        Wrap(
          spacing: tokens.spacing.sm,
          runSpacing: tokens.spacing.sm,
          children: [
            FilledButton.icon(
              key: const ValueKey('prep-follow-up'),
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              label: const Text('Ask a follow-up'),
              onPressed: () => unawaited(
                context.push(
                  askNewLocation(
                    q: 'What should I raise in this meeting?',
                    sources: {
                      AskSource.calendar,
                      AskSource.contacts,
                      AskSource.files,
                    },
                    focus: [event.id],
                  ),
                ),
              ),
            ),
            OutlinedButton.icon(
              key: const ValueKey('prep-open-calendar'),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Open in calendar'),
              onPressed: () => openInCalendar(context, ref, event),
            ),
          ],
        ),
        SizedBox(height: tokens.spacing.sm),
        Text(
          'Built on this phone from your calendar, contacts, notes and '
          'notifications. No model wrote it.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

String _firstLine(String body) {
  for (final l in body.split('\n')) {
    final t = l.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isNotEmpty) return t;
  }
  return '';
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    super.key,
    required this.person,
    required this.contactsOn,
    required this.colorIndex,
    required this.onTap,
    required this.onOpenMeeting,
  });
  final PrepPerson person;
  final bool contactsOn;
  final int colorIndex;
  final VoidCallback onTap;
  final ValueChanged<ConnectorItem> onOpenMeeting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;
    final known = [
      if (contactsOn)
        person.inContacts ? 'In your contacts' : 'Not in your contacts',
      ?person.email,
    ].join(' · ');
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.spacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(tokens.radius.md),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  PersonAvatar(
                    name: person.name,
                    photoBase64: person.photoBase64,
                    colorIndex: colorIndex,
                  ),
                  SizedBox(width: tokens.spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(person.name, style: theme.textTheme.bodyLarge),
                        if (known.isNotEmpty)
                          Text(
                            known,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (person.otherMeetings.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                left: 32 + tokens.spacing.md,
                top: tokens.spacing.xs,
              ),
              child: Wrap(
                spacing: tokens.spacing.sm,
                children: [
                  for (final m in person.otherMeetings)
                    ActionChip(
                      label: Text(
                        'Also: ${m.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: () => onOpenMeeting(m),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(tokens.radius.md),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: tokens.spacing.sm),
          child: Row(
            children: [
              Icon(icon, size: 20, color: scheme.primary),
              SizedBox(width: tokens.spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge,
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                SizedBox(width: tokens.spacing.sm),
                Text(
                  trailing!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
