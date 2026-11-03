/// The "Better answers" label a model card shows on a ~3B model the device
/// runs comfortably (shared by Discover and onboarding).
library;

import 'package:flutter/material.dart';

class BetterAnswersLabel extends StatelessWidget {
  const BetterAnswersLabel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      'Better answers',
      key: const ValueKey('better-answers-label'),
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
