/// First-run onboarding flow (PRD v0.3 WS2). Four calm steps, skippable at
/// any point, shown ONCE (the store flag is written on finish OR skip):
///
///   welcome → pick your first model → one-tap download → ready → chat
///
/// A fresh install reaches a working first chat without ever seeing the raw
/// Hugging Face firehose or a quant menu: the "pick" step is the curated
/// catalog only, with the device-appropriate model pre-selected and badged
/// "Recommended", and the download auto-picks the right quant.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/device_info/model_tier.dart';
import '../../../core/theme/brand_star.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../data/models/starter_catalog.dart';
import '../state/onboarding_controller.dart';

/// A few concrete things a first-timer can try — shown on the "ready" step so
/// the handoff into chat says what the model is *for*, not just "done".
const _suggestedPrompts = <String>[
  'Explain how a rainbow forms, simply',
  'Write a short poem about the sea',
  'Give me 3 quick dinner ideas',
];

enum _Step { welcome, pick, download, ready }

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  _Step _step = _Step.welcome;
  StarterModel? _selected;

  /// Mark onboarding seen (finish OR skip) and leave for chat. Persisting on
  /// BOTH paths is what makes it show exactly once — a user who skips with no
  /// model still never sees it again.
  Future<void> _finish() async {
    final store = await ref.read(onboardingStoreProvider.future);
    await store.markComplete();
    if (mounted) context.go('/chat');
  }

  /// The ready-step exit: mark onboarding done, then land the user IN a chat
  /// thread with the just-installed model already loaded — not on the empty
  /// conversation list. Push the thread on top of `/chat` so the shell (and
  /// back-to-list) sits underneath, exactly like the models-hub download CTA.
  /// [prompt] is a tapped "Try asking" chip: it rides a query param the
  /// `/chat/:id` route turns into `ChatRouteArgs.initialPrompt`, which
  /// auto-sends the first turn (PRD golden path: tap a prompt → streaming
  /// reply).
  Future<void> _startChat({String? prompt}) async {
    final store = await ref.read(onboardingStoreProvider.future);
    await store.markComplete();
    if (!mounted) return;
    final installedId = ref
        .read(onboardingDownloadControllerProvider)
        .value
        ?.installedId;
    final trimmed = prompt?.trim();
    final location = trimmed == null || trimmed.isEmpty
        ? '/chat/new'
        : '/chat/new?prompt=${Uri.encodeQueryComponent(trimmed)}';
    final router = GoRouter.of(context);
    router.go('/chat');
    unawaited(router.push(location, extra: installedId));
  }

  /// Download-step Cancel / Android back: stop the download and return to the
  /// pick step so the flow is never a dead-end (PRD: every long op cancellable,
  /// no dead ends).
  void _cancelDownload() {
    unawaited(ref.read(onboardingDownloadControllerProvider.notifier).cancel());
    setState(() => _step = _Step.pick);
  }

  void _startDownload(StarterModel model) {
    setState(() {
      _selected = model;
      _step = _Step.download;
    });
    ref
        .read(onboardingDownloadControllerProvider.notifier)
        .download(model.repoId);
  }

  @override
  Widget build(BuildContext context) {
    // The download step auto-advances to "ready" the moment the model lands.
    ref.listen(onboardingDownloadControllerProvider, (_, next) {
      if (next.value?.status == OnboardingDownloadStatus.installed &&
          _step == _Step.download) {
        setState(() => _step = _Step.ready);
      }
    });

    // A multi-step wizard on a single route: intercept the system/Android
    // back gesture so it walks back a step (and cancels an in-flight download)
    // instead of popping the whole route — which, on a fresh install where
    // onboarding is the first screen, would exit the app.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        switch (_step) {
          case _Step.welcome:
            break; // nothing behind the first step — stay put
          case _Step.pick:
            setState(() => _step = _Step.welcome);
          case _Step.download:
            _cancelDownload();
          case _Step.ready:
            setState(() => _step = _Step.pick);
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: switch (_step) {
            _Step.welcome => _WelcomeStep(
              onStart: () => setState(() => _step = _Step.pick),
              onSkip: _finish,
            ),
            _Step.pick => _PickStep(
              selected: _selected,
              onSelect: (m) => setState(() => _selected = m),
              onDownload: _startDownload,
              onSkip: _finish,
            ),
            _Step.download => _DownloadStep(
              model: _selected,
              onRetry: () {
                final m = _selected;
                if (m != null) _startDownload(m);
              },
              onPickAnother: () => setState(() => _step = _Step.pick),
              onCancel: _cancelDownload,
            ),
            _Step.ready => _ReadyStep(
              model: _selected,
              onStartChat: (prompt) => _startChat(prompt: prompt),
            ),
          },
        ),
      ),
    );
  }
}

/// Shared page scaffold: generous padding, scroll-safe on short viewports.
class _Page extends StatelessWidget {
  const _Page({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: EdgeInsets.all(tokens.spacing.xl),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({required this.onStart, required this.onSkip});
  final VoidCallback onStart;
  final Future<void> Function() onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return _Page(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(height: tokens.spacing.xl),
          DhruvaStar(size: 96, color: theme.colorScheme.primary),
          SizedBox(height: tokens.spacing.lg),
          Text(
            'Welcome to Dhruva',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          SizedBox(height: tokens.spacing.md),
          Text(
            'A private AI that runs entirely on your phone.',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: tokens.spacing.sm),
          Text(
            'Chat, brainstorm, and get answers — fully offline, once a model '
            'is on your device. Nothing is ever sent to a server.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: tokens.spacing.md),
          Text(
            'Your AI. Your phone. Nobody else\'s business.',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
          SizedBox(height: tokens.spacing.xl),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onStart,
              child: const Text('Get started'),
            ),
          ),
          SizedBox(height: tokens.spacing.sm),
          TextButton(
            onPressed: () => onSkip(),
            child: const Text('Skip for now'),
          ),
        ],
      ),
    );
  }
}

class _PickStep extends ConsumerWidget {
  const _PickStep({
    required this.selected,
    required this.onSelect,
    required this.onDownload,
    required this.onSkip,
  });
  final StarterModel? selected;
  final ValueChanged<StarterModel> onSelect;
  final ValueChanged<StarterModel> onDownload;
  final Future<void> Function() onSkip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final ram = ref.watch(onboardingMemoryProvider).value?.totalBytes;
    final recommended = recommendedStarterModel(ram);

    // Text models only (a first chat model), best-fit-first when RAM is known
    // so the recommended pick and its neighbours lead.
    final models = starterModelCatalog.where((m) => !m.isVision).toList();
    if (ram != null) {
      int tierIndex(StarterModel m) => classifyModelTier(
        fileSizeBytes: m.approxSizeBytes,
        totalRamBytes: ram,
      ).index;
      models.sort((a, b) {
        final byTier = tierIndex(a).compareTo(tierIndex(b));
        return byTier != 0
            ? byTier
            : a.approxSizeBytes.compareTo(b.approxSizeBytes);
      });
    }

    // Default the selection to the recommended pick once RAM is known.
    final active = selected ?? recommended;

    return _Page(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Pick your first model', style: theme.textTheme.headlineSmall),
          SizedBox(height: tokens.spacing.sm),
          Text(
            'One tap downloads it — Dhruva picks the right size for your '
            'phone. You can add more later.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: tokens.spacing.lg),
          for (final model in models) ...[
            _ModelOption(
              model: model,
              selected: model.repoId == active.repoId,
              recommended: model.repoId == recommended.repoId,
              totalRamBytes: ram,
              onTap: () => onSelect(model),
            ),
            SizedBox(height: tokens.spacing.sm),
          ],
          SizedBox(height: tokens.spacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.download_outlined, size: 18),
              onPressed: () => onDownload(active),
              label: Text('Download ${active.displayName}'),
            ),
          ),
          SizedBox(height: tokens.spacing.sm),
          Center(
            child: TextButton(
              onPressed: () => onSkip(),
              child: const Text('Skip for now'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelOption extends StatelessWidget {
  const _ModelOption({
    required this.model,
    required this.selected,
    required this.recommended,
    required this.totalRamBytes,
    required this.onTap,
  });
  final StarterModel model;
  final bool selected;
  final bool recommended;
  final int? totalRamBytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final tier = totalRamBytes == null
        ? null
        : classifyModelTier(
            fileSizeBytes: model.approxSizeBytes,
            totalRamBytes: totalRamBytes!,
          );
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${model.displayName}. ${model.bestFor}. '
          '${_formatBytes(model.approxSizeBytes)}'
          '${recommended ? '. Recommended for your device' : ''}',
      child: InkWell(
        borderRadius: BorderRadius.circular(tokens.radius.md),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(tokens.spacing.md),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(tokens.radius.md),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                size: 22,
              ),
              SizedBox(width: tokens.spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            model.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        if (recommended) ...[
                          SizedBox(width: tokens.spacing.sm),
                          const _RecommendedBadge(),
                        ],
                      ],
                    ),
                    SizedBox(height: tokens.spacing.xs),
                    Text(
                      model.bestFor,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    SizedBox(height: tokens.spacing.xs),
                    Row(
                      children: [
                        Text(
                          _formatBytes(model.approxSizeBytes),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (tier != null) ...[
                          SizedBox(width: tokens.spacing.sm),
                          Text(
                            '·  ${_tierLabel(tier)}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: _tierColor(theme, tokens, tier),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecommendedBadge extends StatelessWidget {
  const _RecommendedBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.sm,
        vertical: tokens.spacing.xs / 2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(tokens.radius.full),
      ),
      child: Text(
        'Recommended',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DownloadStep extends ConsumerWidget {
  const _DownloadStep({
    required this.model,
    required this.onRetry,
    required this.onPickAnother,
    required this.onCancel,
  });
  final StarterModel? model;
  final VoidCallback onRetry;
  final VoidCallback onPickAnother;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final dl = ref.watch(onboardingDownloadControllerProvider).value;
    final status = dl?.status ?? OnboardingDownloadStatus.resolving;
    final failed = status == OnboardingDownloadStatus.failed;
    final name = model?.displayName ?? 'your model';

    return _Page(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: tokens.spacing.xl),
          DhruvaStar(
            size: 72,
            color: failed ? theme.colorScheme.error : theme.colorScheme.primary,
          ),
          SizedBox(height: tokens.spacing.lg),
          Text(
            failed ? 'Download didn\'t finish' : 'Getting $name ready',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          SizedBox(height: tokens.spacing.sm),
          Text(
            failed
                ? (dl?.errorMessage ?? 'Something went wrong.')
                : 'Downloading once, then it runs fully offline on your phone.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: tokens.spacing.xl),
          if (failed) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ),
            SizedBox(height: tokens.spacing.sm),
            TextButton(
              onPressed: onPickAnother,
              child: const Text('Pick another model'),
            ),
          ] else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(tokens.radius.full),
              child: LinearProgressIndicator(
                minHeight: 8,
                value:
                    status == OnboardingDownloadStatus.downloading &&
                        (dl?.progress ?? 0) > 0
                    ? dl!.progress
                    : null,
              ),
            ),
            SizedBox(height: tokens.spacing.sm),
            Text(
              status == OnboardingDownloadStatus.downloading &&
                      (dl?.progress ?? 0) > 0
                  ? '${((dl!.progress) * 100).round()}%'
                  : 'Preparing…',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: tokens.spacing.lg),
            // No dead-end: a large model on a slow link is always cancellable.
            TextButton(onPressed: onCancel, child: const Text('Cancel')),
          ],
        ],
      ),
    );
  }
}

class _ReadyStep extends StatelessWidget {
  const _ReadyStep({required this.model, required this.onStartChat});
  final StarterModel? model;

  /// [prompt] is the tapped "Try asking" chip (null for the plain "Start
  /// chatting" button) — carried into the first chat turn so it actually gets
  /// asked, not discarded.
  final void Function(String? prompt) onStartChat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return _Page(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: tokens.spacing.lg),
          Center(child: DhruvaStar(size: 80, color: theme.colorScheme.primary)),
          SizedBox(height: tokens.spacing.lg),
          Text(
            'You\'re ready',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          SizedBox(height: tokens.spacing.sm),
          Text(
            model == null
                ? 'Your model is installed and runs fully on-device.'
                : '${model!.displayName} is installed and runs fully on your '
                      'phone.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: tokens.spacing.xl),
          Text('Try asking', style: theme.textTheme.titleSmall),
          SizedBox(height: tokens.spacing.sm),
          for (final prompt in _suggestedPrompts) ...[
            _SuggestedPromptChip(
              prompt: prompt,
              onTap: () => onStartChat(prompt),
            ),
            SizedBox(height: tokens.spacing.sm),
          ],
          SizedBox(height: tokens.spacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              onPressed: () => onStartChat(null),
              label: const Text('Start chatting'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestedPromptChip extends StatelessWidget {
  const _SuggestedPromptChip({required this.prompt, required this.onTap});
  final String prompt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return InkWell(
      borderRadius: BorderRadius.circular(tokens.radius.md),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.md,
          vertical: tokens.spacing.md,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(tokens.radius.md),
        ),
        child: Row(
          children: [
            Expanded(child: Text(prompt, style: theme.textTheme.bodyMedium)),
            Icon(
              Icons.arrow_forward,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

String _tierLabel(ModelTier tier) => switch (tier) {
  ModelTier.comfortable => 'Runs great',
  ModelTier.possible => 'Should run',
  ModelTier.notRecommended => 'May be slow',
};

Color _tierColor(ThemeData theme, DhruvaTokens tokens, ModelTier tier) =>
    switch (tier) {
      ModelTier.comfortable => tokens.success,
      ModelTier.possible => theme.colorScheme.onSurfaceVariant,
      ModelTier.notRecommended => tokens.warning,
    };

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
}
