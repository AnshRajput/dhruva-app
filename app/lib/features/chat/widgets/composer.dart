/// Bottom composer (chat-spec.md §1.2): multiline input, send/stop
/// crossfade, settings entry point, trust mark above it (§1.3), plus the
/// Loop 6 hold-to-talk mic button (D1): a live "Listening…" overlay swaps
/// in for the text field while the button is held, and the finalized
/// transcript lands in the field, editable, on release — never auto-sent
/// (chat-spec.md's own philosophy: composer content is always user-owned
/// until they hit send).
///
/// Loop 7 (vision): an attach button — gated on [isMultimodal] (gate G3,
/// hidden entirely for a text-only or unloaded model) — offers Photo
/// Library/Camera via [ImageAttacher], downscales the pick
/// ([downscaleImage]), and shows it as a removable thumbnail chip above the
/// input until send. "Extract text" is a quick-action next to that chip
/// (preset prompt, `vision_presets.dart`) rather than a whole second UI
/// surface — "Describe" needs none, it's just normal chat with an image
/// attached.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../vision/image_attach_source.dart';
import '../../voice/state/voice_input_controller.dart';
import '../../voice/widgets/mic_button.dart';
import '../state/image_downscale.dart';
import '../state/vision_presets.dart';
import 'brand_motif.dart';

class Composer extends ConsumerStatefulWidget {
  final bool isGenerating;

  /// Loop 7 gate G3: shows the attach button only when the conversation's
  /// currently-loaded model supports vision. Defaults false (text-only /
  /// no model loaded) — the pre-Loop-7 behavior every existing caller keeps
  /// without passing this.
  final bool isMultimodal;
  final void Function(String text, Uint8List? imageBytes) onSend;
  final VoidCallback onCancel;
  final VoidCallback onOpenSettings;

  const Composer({
    super.key,
    required this.isGenerating,
    this.isMultimodal = false,
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
  Uint8List? _attachedImage;

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
    if (widget.isGenerating || (!_hasText && _attachedImage == null)) return;
    final text = _controller.text;
    final image = _attachedImage;
    _controller.clear();
    setState(() {
      _hasText = false;
      _attachedImage = null;
    });
    widget.onSend(text, image);
  }

  Future<void> _pickImage(ImageAttachSource source) async {
    Navigator.of(context).pop(); // close the attach sheet first.
    try {
      final bytes = await ref.read(imageAttacherProvider).pickImage(source);
      if (bytes == null || !mounted) return; // user cancelled the picker.
      final downscaled = await downscaleImage(bytes);
      if (!mounted) return;
      setState(() => _attachedImage = downscaled);
    } on ImageAttachPermissionDenied catch (_) {
      if (!mounted) return;
      final label = source == ImageAttachSource.camera
          ? 'Camera'
          : 'Photo library';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$label access is required to attach an image — enable it in '
            "your device's app settings.",
          ),
        ),
      );
    } on UnsupportedImageFormat catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Animated GIFs are not supported — attach a photo.'),
        ),
      );
    } on PlatformException catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't attach that image.")),
      );
    } catch (_) {
      // QA HIGH: a corrupt/truncated image makes `downscaleImage`'s dart:ui
      // decode throw a bare Exception — surface the same "couldn't attach"
      // message instead of letting it crash the pick flow.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't attach that image.")),
      );
    }
  }

  void _openAttachSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photo Library'),
              onTap: () => _pickImage(ImageAttachSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera'),
              onTap: () => _pickImage(ImageAttachSource.camera),
            ),
          ],
        ),
      ),
    );
  }

  void _removeAttachedImage() => setState(() => _attachedImage = null);

  void _extractText() {
    final image = _attachedImage;
    if (image == null) return;
    _controller.clear();
    setState(() {
      _attachedImage = null;
      _hasText = false;
    });
    widget.onSend(extractTextPrompt, image);
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
              if (_attachedImage != null) ...[
                _AttachedImageChip(
                  imageBytes: _attachedImage!,
                  onRemove: _removeAttachedImage,
                  onExtractText: _extractText,
                ),
                SizedBox(height: tokens.spacing.sm),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'System prompt & sampling',
                    icon: const Icon(Icons.tune),
                    onPressed: widget.onOpenSettings,
                  ),
                  if (widget.isMultimodal)
                    IconButton(
                      tooltip: 'Attach image',
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      onPressed: _openAttachSheet,
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
                    enabled:
                        widget.isGenerating ||
                        _hasText ||
                        _attachedImage != null,
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

/// Loop 7: the picked (already downscaled) image shown above the input
/// before send, with a remove affordance and the "Extract text" quick
/// action (chat-spec.md vision addendum — a preset prompt, not a second UI
/// surface).
class _AttachedImageChip extends StatelessWidget {
  final Uint8List imageBytes;
  final VoidCallback onRemove;
  final VoidCallback onExtractText;

  const _AttachedImageChip({
    required this.imageBytes,
    required this.onRemove,
    required this.onExtractText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Row(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(tokens.radius.sm),
              child: Image.memory(
                imageBytes,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
              ),
            ),
            // Designer BLOCKING: was a bare GestureDetector (~20px, no
            // tooltip/Semantics). IconButton gives a tooltip + semantic label
            // + a ≥44px tap target for free, without inflating the 14px badge
            // (same fix as Loop 4's message_bubble action icons).
            Positioned(
              top: -16,
              right: -16,
              child: IconButton(
                onPressed: onRemove,
                tooltip: 'Remove image',
                iconSize: 14,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: CircleAvatar(
                  radius: 10,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(width: tokens.spacing.sm),
        TextButton.icon(
          onPressed: onExtractText,
          icon: const Icon(Icons.text_snippet_outlined, size: 16),
          label: const Text('Extract text'),
        ),
      ],
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
