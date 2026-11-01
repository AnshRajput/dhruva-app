/// "See day" (`/day`): direction B's timeline. Wave 1 ships the empty
/// timeline; Wave 3 fills it with calendar events and free time.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/next_step_card.dart';
import '../state/day_text.dart';

class DayTimelineScreen extends StatelessWidget {
  const DayTimelineScreen({super.key, this.now});

  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    return Scaffold(
      appBar: AppBar(title: Text(formatDayLine(now ?? DateTime.now()))),
      body: ListView(
        padding: EdgeInsets.all(tokens.spacing.base),
        children: [
          NextStepCard(
            icon: Icons.timeline_rounded,
            title: 'Nothing on your day yet',
            body:
                'Meetings from your calendar show up here as a timeline, with '
                'your free time in between.',
            actionLabel: 'See connectors',
            actionKey: const ValueKey('day-connect-calendar'),
            onAction: () => context.push('/settings/connectors'),
          ),
        ],
      ),
    );
  }
}
