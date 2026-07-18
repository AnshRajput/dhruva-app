/// Playground + AI news (PlaygroundMock.astro; VIDEO_FIXES.md P2 #7). Two tabs:
///
/// - Playground: pick TWO installed models, type one prompt, run it through
///   BOTH via the shared on-device engine, and read their streaming replies +
///   live tok/s side by side. A live Temperature (+ Top-P / Max tokens) control
///   applies to the run. ADR-001 single-session means the two runs are
///   serialized (see `playground_controller.dart`); the UI shows both columns.
/// - AI news: an opt-in on-device digest of small GGUF models worth trying,
///   fetched only on tap via the existing HF client; each item deep-links into
///   the model detail/download flow.
///
/// Every color/text style comes from the theme / `DhruvaTokens`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../data/downloads/storage_manager.dart';
import '../../../data/hf_api/models/hf_model_summary.dart';
import '../state/ai_news_controller.dart';
import '../state/playground_controller.dart';
import '../state/playground_installed_models_provider.dart';

class PlaygroundScreen extends StatelessWidget {
  const PlaygroundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Playground'),
          actions: const [
            Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(child: _ABChip()),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Playground'),
              Tab(text: 'AI news'),
            ],
          ),
        ),
        body: const TabBarView(children: [_PlaygroundTab(), _AiNewsTab()]),
      ),
    );
  }
}

class _ABChip extends StatelessWidget {
  const _ABChip();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.sm,
        vertical: tokens.spacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(tokens.radius.full),
      ),
      child: Text(
        'A / B',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Playground tab
// ---------------------------------------------------------------------------

class _PlaygroundTab extends ConsumerStatefulWidget {
  const _PlaygroundTab();

  @override
  ConsumerState<_PlaygroundTab> createState() => _PlaygroundTabState();
}

class _PlaygroundTabState extends ConsumerState<_PlaygroundTab> {
  final _promptCtrl = TextEditingController();

  @override
  void dispose() {
    _promptCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final modelsAsync = ref.watch(playgroundInstalledModelsProvider);
    return switch (modelsAsync) {
      AsyncData(:final value) =>
        value.length < 2
            ? _InstallMorePrompt(installedCount: value.length)
            : _CompareBody(models: value, promptCtrl: _promptCtrl),
      AsyncError() => _CenterMessage(
        icon: Icons.error_outline,
        message: 'Could not read installed models.',
        actionLabel: 'Retry',
        onAction: () => ref.invalidate(playgroundInstalledModelsProvider),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _InstallMorePrompt extends StatelessWidget {
  final int installedCount;
  const _InstallMorePrompt({required this.installedCount});

  @override
  Widget build(BuildContext context) {
    final message = installedCount == 0
        ? 'The Playground compares two models head to head. Install at least '
              'two GGUF models to get started.'
        : 'You have one model installed. Add one more to compare two side by '
              'side.';
    return _CenterMessage(
      icon: Icons.science_outlined,
      message: message,
      actionLabel: 'Browse models',
      onAction: () => GoRouter.of(context).go('/models'),
    );
  }
}

class _CenterMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  const _CenterMessage({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

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
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            SizedBox(height: tokens.spacing.base),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: tokens.spacing.base),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _CompareBody extends ConsumerWidget {
  final List<InstalledModelInfo> models;
  final TextEditingController promptCtrl;
  const _CompareBody({required this.models, required this.promptCtrl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final state = ref.watch(playgroundControllerProvider);
    final controller = ref.read(playgroundControllerProvider.notifier);

    final modelA = _resolve(state.modelAId, models.first);
    final modelB = _resolve(
      state.modelBId,
      models.firstWhere((m) => m.id != modelA.id, orElse: () => models[1]),
    );

    // Winner-ish framing: once BOTH columns finish, mark the faster one. It's
    // an honest speed verdict (tok/s), not a quality judgement the app can't
    // make. Ties (or 0/0) go to A so exactly one badge ever shows.
    final bothDone =
        state.runA.status == RunStatus.done &&
        state.runB.status == RunStatus.done;
    final aFastest =
        bothDone && state.runA.finalTokPerSec >= state.runB.finalTokPerSec;
    final bFastest = bothDone && !aFastest;

    return ListView(
      padding: EdgeInsets.all(tokens.spacing.md),
      children: [
        Text(
          'One prompt, two models, side by side — compare their speed and '
          'answers, then keep the one you like.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(height: tokens.spacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _ModelCard(
                model: modelA,
                accent: theme.colorScheme.primary,
                enabled: !state.isRunning,
                onTap: () => _pickModel(
                  context,
                  ref,
                  models,
                  modelA.id,
                  (id) => controller.setModelA(id),
                ),
              ),
            ),
            SizedBox(width: tokens.spacing.sm),
            Expanded(
              child: _ModelCard(
                model: modelB,
                accent: theme.colorScheme.secondary,
                enabled: !state.isRunning,
                onTap: () => _pickModel(
                  context,
                  ref,
                  models,
                  modelB.id,
                  (id) => controller.setModelB(id),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: tokens.spacing.md),
        TextField(
          controller: promptCtrl,
          minLines: 2,
          maxLines: 4,
          enabled: !state.isRunning,
          style: theme.textTheme.bodyLarge,
          decoration: const InputDecoration(
            hintText: 'Ask both models the same thing…',
          ),
        ),
        SizedBox(height: tokens.spacing.md),
        _SliderRow(
          label: 'Temperature',
          value: state.temperature,
          min: 0,
          max: 2,
          divisions: 40,
          format: (v) => v.toStringAsFixed(2),
          enabled: !state.isRunning,
          onChanged: controller.setTemperature,
        ),
        _SliderRow(
          label: 'Top-P',
          value: state.topP,
          min: 0,
          max: 1,
          divisions: 100,
          format: (v) => v.toStringAsFixed(2),
          enabled: !state.isRunning,
          onChanged: controller.setTopP,
        ),
        _SliderRow(
          label: 'Max tokens',
          value: state.maxTokens.toDouble(),
          min: 16,
          max: 1024,
          divisions: 63,
          format: (v) => v.round().toString(),
          enabled: !state.isRunning,
          onChanged: (v) => controller.setMaxTokens(v.round()),
        ),
        SizedBox(height: tokens.spacing.md),
        state.isRunning
            ? OutlinedButton.icon(
                onPressed: controller.cancel,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              )
            : FilledButton.icon(
                onPressed: () => controller.run(
                  prompt: promptCtrl.text,
                  modelA: modelA,
                  modelB: modelB,
                ),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Run on both'),
              ),
        SizedBox(height: tokens.spacing.md),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _ResultColumn(
                  model: modelA,
                  slot: state.runA,
                  accent: theme.colorScheme.primary,
                  isFastest: aFastest,
                ),
              ),
              SizedBox(width: tokens.spacing.sm),
              Expanded(
                child: _ResultColumn(
                  model: modelB,
                  slot: state.runB,
                  accent: theme.colorScheme.secondary,
                  isFastest: bFastest,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  InstalledModelInfo _resolve(int? id, InstalledModelInfo fallback) {
    if (id == null) return fallback;
    return models.firstWhere((m) => m.id == id, orElse: () => fallback);
  }

  Future<void> _pickModel(
    BuildContext context,
    WidgetRef ref,
    List<InstalledModelInfo> models,
    int currentId,
    void Function(int) onPick,
  ) async {
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: RadioGroup<int>(
          groupValue: currentId,
          onChanged: (v) => Navigator.of(context).pop(v),
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.symmetric(vertical: tokens.spacing.sm),
            children: [
              for (final m in models)
                RadioListTile<int>(
                  value: m.id,
                  title: Text(_shortName(m), overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    m.quant ?? m.fileName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) onPick(picked);
  }
}

class _ModelCard extends StatelessWidget {
  final InstalledModelInfo model;
  final Color accent;
  final bool enabled;
  final VoidCallback onTap;
  const _ModelCard({
    required this.model,
    required this.accent,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(tokens.radius.md),
      child: Container(
        padding: EdgeInsets.all(tokens.spacing.sm),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(tokens.radius.md),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _shortName(model),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(color: accent),
                  ),
                ),
                Icon(
                  Icons.unfold_more,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            SizedBox(height: tokens.spacing.xs),
            Text(
              model.quant ?? model.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultColumn extends StatelessWidget {
  final InstalledModelInfo model;
  final RunSlot slot;
  final Color accent;

  /// True on the column that finished with the higher tok/s once both are done.
  final bool isFastest;
  const _ResultColumn({
    required this.model,
    required this.slot,
    required this.accent,
    this.isFastest = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final isError = slot.status == RunStatus.error;
    return Container(
      padding: EdgeInsets.all(tokens.spacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(tokens.radius.md),
        border: Border.all(
          color: isFastest ? accent : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _shortName(model),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(color: accent),
                ),
              ),
              if (isFastest) _FastestBadge(accent: accent),
            ],
          ),
          SizedBox(height: tokens.spacing.xs),
          Row(
            children: [
              if (slot.status == RunStatus.loading ||
                  slot.status == RunStatus.streaming)
                Padding(
                  padding: EdgeInsets.only(right: tokens.spacing.xs),
                  child: SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: accent,
                    ),
                  ),
                ),
              Expanded(
                child: Text(
                  _statusLine(slot),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: isError
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (slot.text.isNotEmpty) ...[
            SizedBox(height: tokens.spacing.sm),
            Text(slot.text, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  String _statusLine(RunSlot slot) => switch (slot.status) {
    RunStatus.idle => 'Ready',
    RunStatus.loading => 'Loading model…',
    RunStatus.streaming => '${slot.liveTokPerSec.toStringAsFixed(0)} tok/s',
    RunStatus.done => '${slot.finalTokPerSec.toStringAsFixed(0)} tok/s · done',
    RunStatus.cancelled => 'Stopped',
    RunStatus.error => slot.error ?? 'Error',
  };
}

/// Small pill on the faster column once both runs finish ("winner-ish").
class _FastestBadge extends StatelessWidget {
  final Color accent;
  const _FastestBadge({required this.accent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.xs,
        vertical: tokens.spacing.xs / 2,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(tokens.radius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt, size: 12, color: accent),
          SizedBox(width: tokens.spacing.xs / 2),
          Text(
            'Fastest',
            style: theme.textTheme.labelSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) format;
  final bool enabled;
  final ValueChanged<double> onChanged;
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: theme.textTheme.labelLarge),
            Text(
              format(value),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
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
          onChanged: enabled ? onChanged : null,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// AI news tab
// ---------------------------------------------------------------------------

class _AiNewsTab extends ConsumerWidget {
  const _AiNewsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    final digest = ref.watch(aiNewsControllerProvider);
    final controller = ref.read(aiNewsControllerProvider.notifier);

    return ListView(
      padding: EdgeInsets.all(tokens.spacing.md),
      children: [
        switch (digest) {
          AsyncData(:final value) when value == null => _DigestCard(
            subtitle:
                'Discover fresh sub-2B models that run on your phone · '
                'fetched from Hugging Face only when you tap',
            trailing: FilledButton(
              onPressed: controller.load,
              child: const Text('Load'),
            ),
          ),
          AsyncData(:final value) => _DigestLoaded(items: value!),
          AsyncError() => _DigestCard(
            subtitle: 'Could not reach Hugging Face. Check your connection.',
            trailing: TextButton(
              onPressed: controller.load,
              child: const Text('Retry'),
            ),
          ),
          _ => const _DigestCard(
            subtitle: 'Loading this week’s picks…',
            trailing: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        },
      ],
    );
  }
}

class _DigestLoaded extends StatelessWidget {
  final List<HfModelSummary> items;
  const _DigestLoaded({required this.items});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    final subtitle = items.isEmpty
        ? 'No sub-2B releases surfaced right now · opt-in digest'
        : '${items.length} sub-2B GGUF releases worth trying · opt-in digest';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DigestCard(subtitle: subtitle),
        SizedBox(height: tokens.spacing.sm),
        for (final m in items) _NewsItem(model: m),
        if (items.isNotEmpty) ...[
          SizedBox(height: tokens.spacing.xs),
          Builder(
            builder: (context) {
              final theme = Theme.of(context);
              return Text(
                'Tap a model to preview and install it.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

/// The mk-news card: left secondary rail + "This week in on-device AI" + a
/// subtitle, optionally with a trailing action (load / retry / spinner).
class _DigestCard extends StatelessWidget {
  final String subtitle;
  final Widget? trailing;
  const _DigestCard({required this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Container(
      padding: EdgeInsets.all(tokens.spacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(tokens.radius.md),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: theme.colorScheme.secondary,
                borderRadius: BorderRadius.circular(tokens.radius.full),
              ),
            ),
            SizedBox(width: tokens.spacing.sm),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This week in on-device AI',
                    style: theme.textTheme.titleSmall,
                  ),
                  SizedBox(height: tokens.spacing.xs),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              SizedBox(width: tokens.spacing.sm),
              Center(child: trailing!),
            ],
          ],
        ),
      ),
    );
  }
}

class _NewsItem extends StatelessWidget {
  final HfModelSummary model;
  const _NewsItem({required this.model});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(_shortName(model.id), overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${_compact(model.downloads)} downloads · ${_compact(model.likes)} likes',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => GoRouter.of(
        context,
      ).push('/models/repo/${Uri.encodeComponent(model.id)}'),
    );
  }
}

String _shortName(Object model) {
  final id = model is InstalledModelInfo ? model.repoId : model as String;
  final last = id.contains('/') ? id.split('/').last : id;
  return last.replaceAll(RegExp(r'-?GGUF$', caseSensitive: false), '');
}

String _compact(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '$n';
}
