/// Chat empty states (chat-spec.md §7).
library;

import 'package:flutter/material.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import 'brand_motif.dart';

class NoModelInstalledView extends StatelessWidget {
  final VoidCallback onBrowseModels;
  const NoModelInstalledView({super.key, required this.onBrowseModels});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    // Scroll-safe: with the value copy below, the content can exceed a short
    // viewport (small phones, split-screen). Centre it when it fits, scroll
    // when it doesn't — instead of a RenderFlex overflow.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: EdgeInsets.all(tokens.spacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DhruvaStar(size: 96, color: theme.colorScheme.primary),
                SizedBox(height: tokens.spacing.lg),
                Text(
                  'No model installed yet',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                SizedBox(height: tokens.spacing.sm),
                Text(
                  'Pick a model from Hugging Face to start chatting — fully '
                  'offline once it\'s on your device.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: tokens.spacing.md),
                // Value made explicit (VIDEO_FIXES #6 / CLAUDE.md "real
                // value"): the concrete use case, then the brand tagline.
                Text(
                  'A private AI that runs entirely on your phone — chat, '
                  'analyze photos, and talk. Nothing is sent to any server.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: tokens.spacing.sm),
                Text(
                  'Your AI. Your phone. Nobody else\'s business.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
                SizedBox(height: tokens.spacing.lg),
                FilledButton(
                  onPressed: onBrowseModels,
                  child: const Text('Browse models'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// WS3: the empty state for a conversation that HAS a model loaded but no
/// messages yet. Instead of a dead "Say hello" placeholder, it offers a few
/// tappable starter prompts — one tap sends the prompt straight into chat, so
/// a first-time user sees a working reply without having to think of anything
/// to type (PRD golden path: "land in chat with suggested prompts → tap one").
class SuggestedPrompts extends StatelessWidget {
  /// Called with the prompt text when the user taps a starter. The screen
  /// wires this to `ChatController.sendMessage`.
  final ValueChanged<String> onSelect;

  /// True when the loaded model can see images (the composer's attach button
  /// is showing). Drives the vision hint below — advertised "analyze photos"
  /// (see `NoModelInstalledView`) needs a reachable path, so the empty chat
  /// says how to get there for whatever state the user's models are in.
  final bool isMultimodal;

  /// True when a fully-ready vision model is installed but NOT the one loaded
  /// — the hint offers to switch to it rather than sending the user to
  /// download one they already have.
  final bool hasVisionModelInstalled;

  /// Opens the model library (curated catalog carries a vision card). Null in
  /// contexts that don't wire the hint (e.g. widget tests); the hint is then
  /// omitted rather than rendering a dead tap.
  final VoidCallback? onGetVisionModel;

  /// Opens the model picker to switch to an already-installed vision model.
  final VoidCallback? onSwitchModel;

  const SuggestedPrompts({
    super.key,
    required this.onSelect,
    this.isMultimodal = false,
    this.hasVisionModelInstalled = false,
    this.onGetVisionModel,
    this.onSwitchModel,
  });

  /// General-purpose, model-agnostic starters. Kept short and concrete so a
  /// small on-device model gives a satisfying first answer. First entry
  /// mirrors the website chat mockup verbatim.
  static const prompts = <_Starter>[
    _Starter(
      Icons.code_rounded,
      'Explain a stack in one line, then show a Dart example.',
    ),
    _Starter(Icons.auto_stories_outlined, 'Write a haiku about the ocean.'),
    _Starter(
      Icons.restaurant_outlined,
      'Give me 3 quick dinner ideas with chicken.',
    ),
    _Starter(Icons.lightbulb_outline, 'Explain how a rainbow forms, simply.'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return SingleChildScrollView(
      padding: EdgeInsets.all(tokens.spacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: DhruvaStar(size: 64, color: theme.colorScheme.primary)),
          SizedBox(height: tokens.spacing.md),
          Text(
            'Ready when you are',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          SizedBox(height: tokens.spacing.xs),
          Text(
            'Ask anything, or tap a prompt to start.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: tokens.spacing.lg),
          Text(
            'SUGGESTED',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          SizedBox(height: tokens.spacing.sm),
          for (final starter in prompts) ...[
            _StarterCard(starter: starter, onTap: () => onSelect(starter.text)),
            SizedBox(height: tokens.spacing.sm),
          ],
          if (_visionHint case final hint?) ...[
            SizedBox(height: tokens.spacing.xs),
            hint,
          ],
        ],
      ),
    );
  }

  /// The one-line "you can analyze photos" hint, shaped to the user's current
  /// model state, or null when there's nothing actionable to show (or the
  /// screen didn't wire the navigation callbacks). Makes the advertised vision
  /// value reachable from the empty chat instead of a dead promise.
  Widget? get _visionHint {
    if (isMultimodal) {
      // Composer already shows the attach button — just point at it.
      return const _VisionHint(
        text: 'Tap the photo button below to analyze an image.',
      );
    }
    if (hasVisionModelInstalled && onSwitchModel != null) {
      return _VisionHint(
        text: 'Switch to your vision model to analyze photos',
        onTap: onSwitchModel,
      );
    }
    if (onGetVisionModel != null) {
      return _VisionHint(
        text: 'Get a vision model to analyze photos',
        onTap: onGetVisionModel,
      );
    }
    return null;
  }
}

/// A calm, secondary vision hint under the suggested prompts. Tappable when
/// [onTap] is set (routes to the library / model picker), otherwise a plain
/// informational line (the vision model is already loaded).
class _VisionHint extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  const _VisionHint({required this.text, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final row = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.image_outlined,
          size: 16,
          color: theme.colorScheme.secondary,
        ),
        SizedBox(width: tokens.spacing.xs),
        Flexible(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.secondary,
            ),
          ),
        ),
        if (onTap != null) ...[
          SizedBox(width: tokens.spacing.xs),
          Icon(
            Icons.arrow_forward,
            size: 14,
            color: theme.colorScheme.secondary,
          ),
        ],
      ],
    );
    if (onTap == null) return row;
    return InkWell(
      borderRadius: BorderRadius.circular(tokens.radius.sm),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: tokens.spacing.sm),
        child: row,
      ),
    );
  }
}

class _Starter {
  final IconData icon;
  final String text;
  const _Starter(this.icon, this.text);
}

class _StarterCard extends StatelessWidget {
  final _Starter starter;
  final VoidCallback onTap;
  const _StarterCard({required this.starter, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(tokens.radius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radius.md),
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.md),
          child: Row(
            children: [
              Icon(starter.icon, size: 18, color: theme.colorScheme.primary),
              SizedBox(width: tokens.spacing.sm),
              Expanded(
                child: Text(
                  starter.text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              SizedBox(width: tokens.spacing.xs),
              Icon(
                Icons.north_east_rounded,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NoConversationsView extends StatelessWidget {
  final VoidCallback onNewChat;
  const NoConversationsView({super.key, required this.onNewChat});

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
            DhruvaStar(size: 72, color: theme.colorScheme.primary),
            SizedBox(height: tokens.spacing.lg),
            Text(
              'Start your first conversation',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            SizedBox(height: tokens.spacing.sm),
            Text(
              'Your chats stay on this device — no account, no cloud, no '
              'one watching.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: tokens.spacing.sm),
            TrustMark(style: theme.textTheme.bodyMedium),
            SizedBox(height: tokens.spacing.lg),
            FilledButton(onPressed: onNewChat, child: const Text('New chat')),
          ],
        ),
      ),
    );
  }
}
