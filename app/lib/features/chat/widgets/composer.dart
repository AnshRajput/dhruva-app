/// Bottom composer (chat-spec.md §1.2): multiline input, send/stop
/// crossfade, settings entry point, trust mark above it (§1.3), plus the
/// Loop 6 hold-to-talk mic button (D1): a live "Listening…" overlay swaps
/// in for the text field while the button is held, and the finalized
/// transcript lands in the field, editable, on release — never auto-sent
/// (chat-spec.md's own philosophy: composer content is always user-owned
/// until they hit send).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import '../../voice/state/voice_input_controller.dart';
import '../../voice/widgets/mic_button.dart';
import 'brand_motif.dart';

class Composer extends ConsumerStatefulWidget {
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
  ConsumerState<Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<Composer> {
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

  void _appendFinalized(String text) {
    final existing = _controller.text;
    final needsSpace = existing.isNotEmpty && !existing.endsWith(' ');
    _controller.text = existing.isEmpty
        ? text
        : '$existing${needsSpace ? ' ' : ''}$text';
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  void _onNoModel() => context.push('/models');

  void _onPermissionDenied() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Microphone access is required for voice input — enable it in '
          "your device's app settings.",
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final listening =
        ref.watch(voiceInputControllerProvider).phase ==
        VoiceInputPhase.listening;
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
                    child: listening
                        ? _ListeningOverlay(theme: theme)
                        : TextField(
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
                  MicButton(
                    onFinalized: _appendFinalized,
                    onNoModel: _onNoModel,
                    onPermissionDenied: _onPermissionDenied,
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

class _ListeningOverlay extends ConsumerWidget {
  final ThemeData theme;
  const _ListeningOverlay({required this.theme});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveText = ref.watch(voiceInputControllerProvider).liveText;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        liveText.isEmpty ? 'Listening…' : liveText,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: liveText.isEmpty
              ? theme.colorScheme.onSurfaceVariant
              : theme.colorScheme.onSurface,
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
