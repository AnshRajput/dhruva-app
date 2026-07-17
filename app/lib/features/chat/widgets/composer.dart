/// Bottom composer (chat-spec.md §1.2): multiline input, send/stop
/// crossfade, settings entry point, trust mark above it (§1.3).
library;

import 'package:flutter/material.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import 'brand_motif.dart';

class Composer extends StatefulWidget {
  final bool isGenerating;
  final ValueChanged<String> onSend;
  final VoidCallback onCancel;
  final VoidCallback onOpenSettings;

  const Composer({
    super.key,
    required this.isGenerating,
    required this.onSend,
    required this.onCancel,
    required this.onOpenSettings,
  });

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.isGenerating || !_hasText) return;
    final text = _controller.text;
    _controller.clear();
    setState(() => _hasText = false);
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return SafeArea(
      top: false,
      // `Material` (not a raw `Container`) so the surface's elevation reads
      // as the theme's own tonal lift (surface-tint overlay, M3's built-in
      // treatment) instead of a hand-rolled shadow — chat-spec.md §1.2.
      child: Material(
        color: theme.colorScheme.surface,
        surfaceTintColor: theme.colorScheme.surfaceTint,
        elevation: tokens.elevation[1].dp,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spacing.md,
            vertical: tokens.spacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Center(child: TrustMark()),
              SizedBox(height: tokens.spacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'System prompt & sampling',
                    icon: const Icon(Icons.tune),
                    onPressed: widget.onOpenSettings,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 6,
                      textInputAction: TextInputAction.newline,
                      style: theme.textTheme.bodyLarge,
                      decoration: InputDecoration(
                        filled: false,
                        border: InputBorder.none,
                        hintText: 'Message Dhruva…',
                        hintStyle: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: tokens.spacing.sm),
                  _SendStopButton(
                    isGenerating: widget.isGenerating,
                    enabled: widget.isGenerating || _hasText,
                    onSend: _submit,
                    onCancel: widget.onCancel,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendStopButton extends StatelessWidget {
  final bool isGenerating;
  final bool enabled;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  const _SendStopButton({
    required this.isGenerating,
    required this.enabled,
    required this.onSend,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return SizedBox(
      width: 40,
      height: 40,
      child: AnimatedSwitcher(
        duration: tokens.motion.fast,
        switchInCurve: tokens.motion.standard,
        switchOutCurve: tokens.motion.standard,
        child: isGenerating
            ? _RoundIconButton(
                key: const ValueKey('stop'),
                icon: Icons.stop_rounded,
                background: theme.colorScheme.errorContainer,
                foreground: theme.colorScheme.onErrorContainer,
                onPressed: onCancel,
              )
            : _RoundIconButton(
                key: const ValueKey('send'),
                icon: Icons.arrow_upward_rounded,
                background: theme.colorScheme.primary,
                foreground: theme.colorScheme.onPrimary,
                onPressed: enabled ? onSend : null,
              ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback? onPressed;

  const _RoundIconButton({
    required super.key,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        shape: const CircleBorder(),
      ),
    );
  }
}
