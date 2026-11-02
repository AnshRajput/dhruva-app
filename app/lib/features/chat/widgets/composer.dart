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
///
/// Chat with a document: the same attach button also offers a PDF/TXT/MD
/// ([onAttachDocument]); attached documents sit above the input as removable
/// chips (name + page/character count), with a "Reading..." chip while one
/// is being extracted and an inline, dismissible error if it cannot be read.
/// For a text-only model the button opens the document picker directly.
library;

import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/identity/app_identity.dart';
import '../../../core/intents/app_settings.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../data/docs/document_repository.dart' show DocumentInfo;
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

  /// Asked before a send clears the input; false keeps the draft untouched
  /// (battery guard's "confirm before starting"). Null = always send.
  final Future<bool> Function()? beforeSend;
  final VoidCallback onCancel;
  final VoidCallback onOpenSettings;

  /// Opens the document picker; null hides document attach (the pre-docs
  /// behavior every existing caller keeps).
  final VoidCallback? onAttachDocument;
  final void Function(int documentId)? onRemoveDocument;
  final VoidCallback? onDismissDocumentError;

  /// "Cancel" on the Reading chip; null shows the chip without one.
  final VoidCallback? onCancelDocumentRead;

  /// Documents already attached to this conversation.
  final List<DocumentInfo> documents;

  /// Name of a document currently being read, or null.
  final String? extractingDocName;

  /// Plain-language reason the last attach failed, or null.
  final String? documentError;

  /// Shown inside the composer surface above the input row (Ask's "Search in"
  /// chips).
  final Widget? header;

  /// Text the field starts with (a prefilled `/ask/new?q=...`); never sent
  /// until the user taps send.
  final String? initialText;

  /// Called whenever the field's text changes (Auto source preview).
  final ValueChanged<String>? onChanged;

  const Composer({
    super.key,
    required this.isGenerating,
    this.onAttachDocument,
    this.onRemoveDocument,
    this.onDismissDocumentError,
    this.onCancelDocumentRead,
    this.documents = const [],
    this.extractingDocName,
    this.documentError,
    this.header,
    this.initialText,
    this.onChanged,
    this.isMultimodal = false,
    required this.onSend,
    this.beforeSend,
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
    final initial = widget.initialText;
    if (initial != null && initial.isNotEmpty) {
      _controller.text = initial;
      _controller.selection = TextSelection.collapsed(offset: initial.length);
      _hasText = initial.trim().isNotEmpty;
    }
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
      widget.onChanged?.call(_controller.text);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.isGenerating || (!_hasText && _attachedImage == null)) return;
    // D3: the input clears the instant send is tapped (not after the battery
    // check or the model load); a declined check puts the draft back.
    final text = _controller.text;
    final image = _attachedImage;
    _controller.clear();
    setState(() {
      _hasText = false;
      _attachedImage = null;
    });
    final gate = widget.beforeSend;
    if (gate != null && !(await gate())) {
      if (!mounted) return;
      _controller.text = text;
      setState(() => _attachedImage = image);
      return;
    }
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

  /// The attach button: a text-only model can only attach a document, so go
  /// straight to the picker; a vision model gets the choice.
  void _onAttachPressed() {
    if (!widget.isMultimodal) {
      widget.onAttachDocument?.call();
    } else {
      _openAttachSheet();
    }
  }

  void _pickDocument() {
    Navigator.of(context).pop(); // close the attach sheet first.
    widget.onAttachDocument?.call();
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
            if (widget.onAttachDocument != null)
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('Document (PDF, TXT, MD)'),
                subtitle: const Text('Ask questions about a file'),
                onTap: _pickDocument,
              ),
          ],
        ),
      ),
    );
  }

  void _removeAttachedImage() => setState(() => _attachedImage = null);

  Future<void> _extractText() async {
    final image = _attachedImage;
    if (image == null) return;
    final gate = widget.beforeSend;
    if (gate != null && !(await gate()) || !mounted) return;
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

  void _onNoModel() => context.push('/models/hub?tab=voice');

  void _onPermissionDenied() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Microphone access is off, so voice input cannot '
          'hear you.',
        ),
        action: SnackBarAction(
          label: 'Open settings',
          onPressed: () => unawaited(ref.read(openAppSettingsProvider)()),
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
              _DocumentArea(
                documents: widget.documents,
                extractingName: widget.extractingDocName,
                error: widget.documentError,
                onRemove: widget.onRemoveDocument,
                onDismissError: widget.onDismissDocumentError,
                onCancelReading: widget.onCancelDocumentRead,
              ),
              if (widget.header != null) widget.header!,
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
                    tooltip: 'Chat settings',
                    icon: const Icon(Icons.tune),
                    onPressed: widget.onOpenSettings,
                  ),
                  if (widget.isMultimodal || widget.onAttachDocument != null)
                    IconButton(
                      tooltip: !widget.isMultimodal
                          ? 'Attach document'
                          : (widget.onAttachDocument != null
                                ? 'Attach image or document'
                                : 'Attach image'),
                      // Reads as what the button offers: photos for a vision
                      // model, a file for a text-only one.
                      icon: Icon(
                        widget.isMultimodal
                            ? Icons.add_photo_alternate_outlined
                            : Icons.description_outlined,
                      ),
                      onPressed: widget.extractingDocName != null
                          ? null
                          : _onAttachPressed,
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
                              hintText: 'Message ${AppIdentity.shortName}…',
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
              Text(
                'AI can be wrong. Everything runs on your phone.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chips for the attached documents, the "Reading..." placeholder, and the
/// inline error. Collapses to nothing when there is nothing to show.
class _DocumentArea extends StatelessWidget {
  final List<DocumentInfo> documents;
  final String? extractingName;
  final String? error;
  final void Function(int documentId)? onRemove;
  final VoidCallback? onDismissError;
  final VoidCallback? onCancelReading;

  const _DocumentArea({
    required this.documents,
    required this.extractingName,
    required this.error,
    required this.onRemove,
    required this.onDismissError,
    required this.onCancelReading,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    final empty = documents.isEmpty && extractingName == null && error == null;
    // Reduced motion: no height animation, the area just appears.
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : tokens.motion.fast;
    return AnimatedSize(
      duration: duration,
      curve: tokens.motion.standard,
      alignment: Alignment.topCenter,
      child: empty
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: EdgeInsets.only(bottom: tokens.spacing.sm),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: tokens.spacing.sm,
                  runSpacing: tokens.spacing.xs,
                  children: [
                    for (final d in documents)
                      _DocumentChip(
                        key: ValueKey('doc-chip-${d.id}'),
                        title: d.name,
                        subtitle: d.sizeLabel,
                        onRemove: onRemove == null
                            ? null
                            : () => onRemove!(d.id),
                      ),
                    if (extractingName != null)
                      _DocumentChip(
                        key: const ValueKey('doc-chip-reading'),
                        title: extractingName!,
                        subtitle: 'Reading document…',
                        busy: true,
                        onRemove: onCancelReading,
                        removeTooltip: 'Cancel reading $extractingName',
                      ),
                    if (error != null)
                      _DocumentErrorChip(
                        message: error!,
                        onDismiss: onDismissError,
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// One attached document: icon, file name, "12 pages · 14,498 characters",
/// and a remove button (48dp target). A pill, like the other composer
/// chrome.
class _DocumentChip extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool busy;
  final VoidCallback? onRemove;

  /// Tooltip / spoken label of the close button; defaults to "Remove title".
  final String? removeTooltip;

  const _DocumentChip({
    super.key,
    required this.title,
    required this.subtitle,
    this.busy = false,
    this.onRemove,
    this.removeTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320, minHeight: 48),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(tokens.radius.full),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            left: tokens.spacing.md,
            right: onRemove == null ? tokens.spacing.md : 0,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // One spoken label for the whole chip body; the remove button
              // stays its own control.
              Flexible(
                child: Semantics(
                  label: busy
                      ? 'Reading document $title'
                      : 'Attached document $title, $subtitle',
                  child: ExcludeSemantics(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (busy)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Icon(
                            Icons.description_outlined,
                            size: 18,
                            color: scheme.primary,
                          ),
                        SizedBox(width: tokens.spacing.sm),
                        Flexible(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: scheme.onSurface,
                                ),
                              ),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (onRemove != null)
                IconButton(
                  onPressed: onRemove,
                  tooltip: removeTooltip ?? 'Remove $title',
                  iconSize: 18,
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Why the last attach failed, in plain words, with a dismiss button.
class _DocumentErrorChip extends StatelessWidget {
  final String message;
  final VoidCallback? onDismiss;
  const _DocumentErrorChip({required this.message, this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;
    return Semantics(
      liveRegion: true,
      container: true,
      label: message,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(tokens.radius.lg),
          ),
          child: Padding(
            padding: EdgeInsets.only(left: tokens.spacing.md),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 18,
                  color: scheme.onErrorContainer,
                ),
                SizedBox(width: tokens.spacing.sm),
                Flexible(
                  child: Text(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onDismiss,
                  tooltip: 'Dismiss',
                  iconSize: 18,
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  icon: Icon(Icons.close, color: scheme.onErrorContainer),
                ),
              ],
            ),
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
        // Send <-> Stop reads as ONE control morphing: a small scale from
        // 0.85 with the fade (two coloured discs cross-fading looked muddy).
        // 120 ms in, 90 ms out; reduced motion falls back to the plain fade.
        duration: tokens.motion.instant + const Duration(milliseconds: 20),
        reverseDuration: const Duration(milliseconds: 90),
        switchInCurve: tokens.motion.decelerate,
        switchOutCurve: tokens.motion.decelerate,
        transitionBuilder: (child, animation) =>
            MediaQuery.disableAnimationsOf(context)
            ? FadeTransition(opacity: animation, child: child)
            : FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.85, end: 1).animate(animation),
                  child: child,
                ),
              ),
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
    // Press-in scale on pointer-down; the scale is the feedback, so no ripple.
    return PressableScale.passive(
      passiveEnabled: onPressed != null,
      child: IconButton.filled(
        onPressed: onPressed,
        icon: Icon(icon),
        style: IconButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          shape: const CircleBorder(),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
    );
  }
}
