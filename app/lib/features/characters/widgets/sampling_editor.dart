/// A character's optional default sampling params — one slider per
/// `SamplingParams` field (same ranges/defaults as chat-spec.md §5.2's
/// sampling sheet). `chat/ui/sampling_settings_sheet.dart`'s `_SliderRow` is
/// private to that file, and this form's needs are simpler (no tap-to-type
/// escape hatch, no commit-time-only validation dance — a character's
/// sampling override is optional and low-stakes), so this is a small,
/// deliberate, from-scratch widget rather than an extraction across the
/// ADR-002 feature boundary.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../data/chat/models/sampling_params.dart';

class SamplingEditor extends StatelessWidget {
  final SamplingParams value;
  final ValueChanged<SamplingParams> onChanged;

  const SamplingEditor({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Row(
          label: 'Temperature',
          value: value.temperature,
          min: 0,
          max: 2,
          divisions: 40,
          format: (v) => v.toStringAsFixed(2),
          onChanged: (v) => onChanged(value.copyWith(temperature: v)),
        ),
        _Row(
          label: 'Top-P',
          value: value.topP,
          min: 0,
          max: 1,
          divisions: 100,
          format: (v) => v.toStringAsFixed(2),
          onChanged: (v) => onChanged(value.copyWith(topP: v)),
        ),
        _Row(
          label: 'Top-K',
          value: value.topK.toDouble(),
          min: 0,
          max: 200,
          divisions: 200,
          format: (v) => v.round().toString(),
          onChanged: (v) => onChanged(value.copyWith(topK: v.round())),
        ),
        _Row(
          label: 'Max tokens',
          value: value.maxTokens.toDouble(),
          min: 1,
          max: 4096,
          divisions: 4095,
          format: (v) => v.round().toString(),
          onChanged: (v) => onChanged(value.copyWith(maxTokens: v.round())),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  const _Row({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: theme.textTheme.titleSmall),
              Text(
                format(value),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
