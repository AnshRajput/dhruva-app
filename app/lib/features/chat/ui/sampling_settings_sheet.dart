/// Sampling settings sheet (chat-spec.md §5): system prompt + one slider
/// per `SamplingParams` field, each with a tap-to-type escape hatch,
/// commit-time `validate()` (never per-keystroke), reset-to-defaults.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/failures/app_failure.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../data/chat/models/sampling_params.dart';
import '../state/chat_controller.dart';

Future<void> showSamplingSettingsSheet(
  BuildContext context,
  ChatRouteArgs args,
) {
  final tokens = Theme.of(context).extension<DhruvaTokens>()!;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // Nit 6, chat-spec.md §10: entrance motion.moderate (300ms) / exit
    // motion.fast (150ms). `AnimationStyle` only reads duration/
    // reverseDuration for `showModalBottomSheet` — the entrance/exit
    // CURVE (spec wants decelerate/accelerate) isn't plumbed through by
    // the public API (verified against bottom_sheet.dart: `curve`/
    // `reverseCurve` are never read for this call path), so this is a
    // documented, deliberate partial application, not an oversight —
    // see chat-spec.md §10's own note next to this line.
    sheetAnimationStyle: AnimationStyle(
      duration: tokens.motion.moderate,
      reverseDuration: tokens.motion.fast,
    ),
    builder: (context) => SamplingSettingsSheet(args: args),
  );
}

class SamplingSettingsSheet extends ConsumerStatefulWidget {
  final ChatRouteArgs args;
  const SamplingSettingsSheet({super.key, required this.args});

  @override
  ConsumerState<SamplingSettingsSheet> createState() =>
      _SamplingSettingsSheetState();
}

class _SamplingSettingsSheetState extends ConsumerState<SamplingSettingsSheet> {
  late final TextEditingController _systemPromptCtrl;
  late SamplingParams _draft;
  String? _error;

  @override
  void initState() {
    super.initState();
    final current = ref.read(chatControllerProvider(widget.args)).value;
    _systemPromptCtrl = TextEditingController(
      text: current?.systemPrompt ?? '',
    );
    _draft = current?.samplingParams ?? const SamplingParams();
  }

  @override
  void dispose() {
    _systemPromptCtrl.dispose();
    super.dispose();
  }

  Future<void> _commit() async {
    final controller = ref.read(chatControllerProvider(widget.args).notifier);
    try {
      await controller.setSystemPrompt(_systemPromptCtrl.text);
      await controller.setSamplingParams(_draft);
      if (mounted) Navigator.of(context).pop();
    } on ValidationFailure catch (e) {
      setState(() => _error = e.message);
    }
  }

  void _reset() => setState(() {
    _draft = const SamplingParams();
    _error = null;
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: tokens.spacing.md,
          right: tokens.spacing.md,
          top: tokens.spacing.md,
          bottom: MediaQuery.of(context).viewInsets.bottom + tokens.spacing.md,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'System prompt & sampling',
                style: theme.textTheme.titleMedium,
              ),
              SizedBox(height: tokens.spacing.sm),
              TextField(
                controller: _systemPromptCtrl,
                minLines: 2,
                maxLines: 5,
                style: theme.textTheme.bodyLarge,
                decoration: const InputDecoration(
                  hintText: 'You are a helpful assistant…',
                ),
              ),
              SizedBox(height: tokens.spacing.md),
              _SliderRow(
                label: 'Temperature',
                value: _draft.temperature,
                min: 0,
                max: 2,
                divisions: 40,
                onChanged: (v) =>
                    setState(() => _draft = _draft.copyWith(temperature: v)),
              ),
              _SliderRow(
                label: 'Top-P',
                value: _draft.topP,
                min: 0,
                max: 1,
                divisions: 100,
                onChanged: (v) =>
                    setState(() => _draft = _draft.copyWith(topP: v)),
              ),
              _SliderRow(
                label: 'Top-K',
                value: _draft.topK.toDouble(),
                min: 0,
                max: 200,
                divisions: 200,
                isInt: true,
                onChanged: (v) =>
                    setState(() => _draft = _draft.copyWith(topK: v.round())),
              ),
              _SliderRow(
                label: 'Max tokens',
                value: _draft.maxTokens.toDouble(),
                min: 1,
                max: 4096,
                divisions: 4095,
                isInt: true,
                onChanged: (v) => setState(
                  () => _draft = _draft.copyWith(maxTokens: v.round()),
                ),
              ),
              _SliderRow(
                label: 'Context length',
                value: _draft.contextLength.toDouble(),
                min: 512,
                max: 8192,
                divisions: 30,
                isInt: true,
                onChanged: (v) => setState(
                  () => _draft = _draft.copyWith(contextLength: v.round()),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: EdgeInsets.only(top: tokens.spacing.xs),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              SizedBox(height: tokens.spacing.md),
              TextButton(
                onPressed: _reset,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                child: const Text('Reset to defaults'),
              ),
              SizedBox(height: tokens.spacing.sm),
              FilledButton(onPressed: _commit, child: const Text('Done')),
            ],
          ),
        ),
      ),
    );
  }
}

class _SliderRow extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final bool isInt;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    this.isInt = false,
    required this.onChanged,
  });

  @override
  State<_SliderRow> createState() => _SliderRowState();
}

class _SliderRowState extends State<_SliderRow> {
  var _typing = false;
  late final TextEditingController _textCtrl = TextEditingController(
    text: _format(widget.value),
  );

  String _format(double v) =>
      widget.isInt ? v.round().toString() : v.toStringAsFixed(2);

  @override
  void didUpdateWidget(covariant _SliderRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_typing) _textCtrl.text = _format(widget.value);
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  void _commitTyped() {
    final parsed = double.tryParse(_textCtrl.text);
    if (parsed != null) widget.onChanged(parsed);
    setState(() => _typing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final valueStyle = theme.textTheme.labelLarge?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.label, style: theme.textTheme.titleSmall),
              GestureDetector(
                onTap: () => setState(() => _typing = true),
                child: _typing
                    ? SizedBox(
                        width: 64,
                        child: TextField(
                          controller: _textCtrl,
                          autofocus: true,
                          textAlign: TextAlign.end,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          style: valueStyle,
                          decoration: const InputDecoration(isDense: true),
                          onSubmitted: (_) => _commitTyped(),
                          onEditingComplete: _commitTyped,
                        ),
                      )
                    : Text(_format(widget.value), style: valueStyle),
              ),
            ],
          ),
          Slider(
            value: widget.value.clamp(widget.min, widget.max),
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            onChanged: widget.onChanged,
          ),
        ],
      ),
    );
  }
}
