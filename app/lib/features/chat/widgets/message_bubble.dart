/// Message bubble rendering (chat-spec.md §2). Markdown → `TextTheme`
/// mapping per §2.2's table via `MarkdownStyleSheet`; code blocks (§2.3) get
/// a custom `pre` builder for the language label + copy button, re-rendered
/// on every streaming flush (flutter_markdown_plus tolerates an unclosed
/// fence mid-stream by rendering the rest as a plain paragraph until it
/// closes — acceptable degraded behavior, not a crash, and it self-corrects
/// the moment the closing ``` arrives).
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../core/format/when.dart';
import '../../../core/markdown/safe_markdown.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../data/chat/chat_repository.dart';
import '../../../data/connectors/ask_sources.dart' show ItemSource;
import '../../vision/widgets/image_lightbox.dart';
import '../../voice/state/voice_playback_controller.dart';
import '../state/message_info_x.dart';
import 'answer_source_chips.dart';
import 'reasoning_block.dart';
import 'sources_block.dart';

/// How long the "copied" check stays (a confirmation needs time to be read;
/// a motion token is not a timeout).
const _copiedHold = Duration(milliseconds: 1200);

class MessageBubble extends StatelessWidget {
  final MessageInfo message;
  final bool isStreaming;
  final int? reasoningDurationMs;
  final bool reasoningOpen;

  /// Loop 7: the image attached to this turn (`ChatThreadState.
  /// attachedImages`), rendered as a thumbnail above the bubble's text —
  /// tap opens it full-size (`image_lightbox.dart`).
  final Uint8List? attachedImage;

  final VoidCallback? onRegenerate;
  final VoidCallback? onEdit;

  /// "Action: Draft a reply": the label over a user message that started an
  /// Action chat (the instruction itself is in the system layer).
  final String? actionLabel;

  /// Opens the report flow for this (assistant) reply. Null hides the
  /// action (e.g. previews/tests that don't wire it).
  final VoidCallback? onReport;

  /// Keeps this reply in the Library (Saved). Null hides the action.
  final Future<void> Function()? onSave;

  /// How many open to-dos this reply holds (the "Extract to-dos" output) and
  /// the tap that adds them to the Library. Zero / null hides the action.
  final int todoCount;
  final Future<void> Function()? onAddTodos;

  /// Opens a cited connector item (the chip under a grounded answer). Null
  /// hides the chips (previews/tests that don't wire it).
  final ValueChanged<ItemSource>? onOpenItemSource;

  const MessageBubble({
    super.key,
    required this.message,
    this.isStreaming = false,
    this.reasoningDurationMs,
    this.reasoningOpen = false,
    this.attachedImage,
    this.onRegenerate,
    this.onEdit,
    this.actionLabel,
    this.onReport,
    this.onSave,
    this.todoCount = 0,
    this.onAddTodos,
    this.onOpenItemSource,
  });

  @override
  Widget build(BuildContext context) {
    if (message.role == MessageRole.system) {
      return _SystemBanner(message: message);
    }
    // A reported reply collapses behind a placeholder until the user taps
    // "Show" (local, per-bubble state; the report itself stays saved).
    if (message.reported && message.role == MessageRole.assistant) {
      return _ReportedGate(child: _buildBubble(context));
    }
    return _buildBubble(context);
  }

  Widget _buildBubble(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final isUser = message.role == MessageRole.user;
    final background = isUser
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final onBackground = isUser
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;

    final radius = BorderRadius.only(
      topLeft: Radius.circular(tokens.radius.lg),
      topRight: Radius.circular(tokens.radius.lg),
      bottomLeft: Radius.circular(isUser ? tokens.radius.lg : tokens.radius.xs),
      bottomRight: Radius.circular(
        isUser ? tokens.radius.xs : tokens.radius.lg,
      ),
    );

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 0.84,
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isUser && actionLabel != null)
              Padding(
                padding: EdgeInsets.only(bottom: tokens.spacing.xs),
                child: Text(
                  actionLabel!,
                  key: const ValueKey('action-label'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            Container(
              padding: EdgeInsets.all(tokens.spacing.md),
              decoration: BoxDecoration(
                color: background,
                borderRadius: radius,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (attachedImage != null) ...[
                    _AttachedImageThumbnail(imageBytes: attachedImage!),
                    SizedBox(height: tokens.spacing.sm),
                  ],
                  if ((message.reasoningContent ?? '').isNotEmpty)
                    ReasoningBlock(
                      reasoning: message.reasoningContent!,
                      isOpen: isStreaming && reasoningOpen,
                      durationMs: reasoningDurationMs,
                    ),
                  // QA BUG-1: a finalized (not `isStreaming`), contentless,
                  // reasoningless assistant message used to render an empty
                  // `_MarkdownBody` — the bubble shell + metadata row still
                  // showed around nothing, an honest-looking "ghost bubble".
                  // The mid-stream case (isStreaming, awaiting first token)
                  // is unaffected — chat_thread_screen.dart's own
                  // `_buildMessageItem` still short-circuits to
                  // `SizedBox.shrink()` for that one, before this widget is
                  // even built.
                  if (!isUser &&
                      !isStreaming &&
                      message.content.isEmpty &&
                      (message.reasoningContent ?? '').isEmpty)
                    Text(
                      'No response — try regenerating.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: onBackground,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  else
                    _MarkdownBody(text: message.content, onColor: onBackground),
                ],
              ),
            ),
            if (!isUser && !isStreaming && message.sources.isNotEmpty)
              SourcesBlock(sources: message.sources),
            if (!isUser &&
                !isStreaming &&
                onOpenItemSource != null &&
                message.itemSources.isNotEmpty)
              AnswerSourceChips(
                sources: message.itemSources,
                onOpen: onOpenItemSource!,
              ),
            if (!isUser) ...[
              SizedBox(height: tokens.spacing.xs),
              _MetadataRow(
                message: message,
                onRegenerate: onRegenerate,
                onReport: onReport,
                onSave: onSave,
                todoCount: todoCount,
                onAddTodos: onAddTodos,
              ),
            ],
            if (isUser && onEdit != null) ...[
              SizedBox(height: tokens.spacing.xs),
              _EditAffordance(onEdit: onEdit!),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReportedGate extends StatefulWidget {
  final Widget child;
  const _ReportedGate({required this.child});

  @override
  State<_ReportedGate> createState() => _ReportedGateState();
}

class _ReportedGateState extends State<_ReportedGate> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    if (_shown) return widget.child;
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final muted = theme.colorScheme.onSurfaceVariant;
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 0.84,
        alignment: Alignment.centerLeft,
        child: Container(
          padding: EdgeInsets.only(
            left: tokens.spacing.md,
            right: tokens.spacing.xs,
            top: tokens.spacing.xs,
            bottom: tokens.spacing.xs,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(tokens.radius.lg),
          ),
          child: Row(
            children: [
              Icon(Icons.flag_outlined, size: 16, color: muted),
              SizedBox(width: tokens.spacing.sm),
              Expanded(
                child: Text(
                  "You reported this reply. It's hidden.",
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _shown = true),
                child: const Text('Show'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SystemBanner extends StatelessWidget {
  final MessageInfo message;
  const _SystemBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Align(
      alignment: Alignment.center,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: tokens.spacing.xs),
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.md,
          vertical: tokens.spacing.sm,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.6,
          ),
          borderRadius: BorderRadius.circular(tokens.radius.sm),
        ),
        child: Text(
          message.content,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}

/// Under a reply: when it was written and how fast, then Copy and Regenerate
/// (the two things almost everyone wants), then one overflow menu holding Read
/// aloud, Save to Library, Add to to-dos and Report. One line, never wrapping.
class _MetadataRow extends ConsumerStatefulWidget {
  final MessageInfo message;
  final VoidCallback? onRegenerate;
  final VoidCallback? onReport;
  final Future<void> Function()? onSave;
  final int todoCount;
  final Future<void> Function()? onAddTodos;

  const _MetadataRow({
    required this.message,
    this.onRegenerate,
    this.onReport,
    this.onSave,
    this.todoCount = 0,
    this.onAddTodos,
  });

  @override
  ConsumerState<_MetadataRow> createState() => _MetadataRowState();
}

class _MetadataRowState extends ConsumerState<_MetadataRow> {
  bool _copied = false;
  bool _saved = false;
  bool _todosAdded = false;

  Future<void> _save() async {
    await widget.onSave?.call();
    if (mounted) setState(() => _saved = true);
  }

  Future<void> _addTodos() async {
    await widget.onAddTodos?.call();
    if (mounted) setState(() => _todosAdded = true);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.message.content));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(_copiedHold);
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final onRegenerate = widget.onRegenerate;
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final color = theme.colorScheme.onSurfaceVariant;
    final style = theme.textTheme.labelSmall?.copyWith(color: color);
    final tokPerSec =
        message.tokCount != null && message.genMs != null && message.genMs! > 0
        ? (message.tokCount! / (message.genMs! / 1000)).toStringAsFixed(1)
        : null;
    // Read aloud keeps its one-shot error snackbar (it moved into the menu
    // with the speaker button).
    ref.listen(voicePlaybackControllerProvider, (previous, next) {
      if (next.lastErrorMessageId == message.id &&
          next.lastErrorMessageForId != null &&
          next.lastErrorMessageForId != previous?.lastErrorMessageForId) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.lastErrorMessageForId!)));
      }
    });
    final playback = ref.watch(voicePlaybackControllerProvider);
    final playing = playback.isPlaying(message.id);
    final speaking = playback.isSynthesizing(message.id);
    final hasText = message.content.isNotEmpty;
    final canSave = widget.onSave != null && hasText;
    final canTodos = widget.onAddTodos != null && widget.todoCount > 0;
    final canReport = widget.onReport != null && hasText;
    final hasMenu = hasText || canSave || canTodos || canReport;

    Widget action({
      required VoidCallback? onPressed,
      required String tooltip,
      required IconData icon,
      Color? iconColor,
      bool animateSwap = false,
    }) => IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: animateSwap
          // Copy -> check: a short cross-fade so the confirmation reads.
          ? AnimatedSwitcher(
              duration:
                  tokens.motion.instant + const Duration(milliseconds: 20),
              child: Icon(
                icon,
                key: ValueKey(icon),
                size: 16,
                color: iconColor ?? color,
              ),
            )
          : Icon(icon, size: 16, color: iconColor ?? color),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: kMinInteractiveDimension,
        minHeight: kMinInteractiveDimension,
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            '${timeAgo(message.createdAt)}'
            '${tokPerSec != null ? ' · $tokPerSec tok/s' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        if (hasText) ...[
          SizedBox(width: tokens.spacing.xs),
          action(
            onPressed: _copy,
            tooltip: _copied ? 'Copied' : 'Copy text',
            icon: _copied ? Icons.check : Icons.copy,
            iconColor: _copied ? tokens.success : null,
            animateSwap: true,
          ),
        ],
        if (onRegenerate != null)
          action(
            onPressed: onRegenerate,
            tooltip: 'Regenerate response',
            icon: Icons.refresh,
          ),
        if (hasMenu)
          PopupMenuButton<String>(
            key: const ValueKey('reply-more'),
            tooltip: 'More actions',
            icon: Icon(Icons.more_vert, size: 16, color: color),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            onSelected: (v) {
              switch (v) {
                case 'speak':
                  unawaited(
                    ref
                        .read(voicePlaybackControllerProvider.notifier)
                        .toggle(message.id, message.content),
                  );
                case 'save':
                  unawaited(_save());
                case 'todos':
                  unawaited(_addTodos());
                case 'report':
                  widget.onReport?.call();
              }
            },
            itemBuilder: (context) => [
              if (hasText)
                PopupMenuItem(
                  key: const ValueKey('reply-speak'),
                  value: 'speak',
                  enabled: !speaking,
                  child: Text(playing ? 'Stop reading' : 'Read aloud'),
                ),
              if (canSave)
                PopupMenuItem(
                  key: const ValueKey('save-reply'),
                  value: 'save',
                  enabled: !_saved,
                  child: Text(_saved ? 'Saved to Library' : 'Save to Library'),
                ),
              if (canTodos)
                PopupMenuItem(
                  key: const ValueKey('add-todos'),
                  value: 'todos',
                  enabled: !_todosAdded,
                  child: Text(
                    _todosAdded
                        ? 'Added to to-dos'
                        : 'Add ${widget.todoCount} to your to-dos',
                  ),
                ),
              if (canReport)
                // Play AI-Generated Content policy: in-app report on every
                // reply, one tap away in the menu.
                const PopupMenuItem(
                  key: ValueKey('reply-report'),
                  value: 'report',
                  child: Text('Report this reply'),
                ),
            ],
          ),
      ],
    );
  }
}

/// Loop 7: the image attached to a turn, rendered as a bounded thumbnail —
/// tap opens it full-size via [showImageLightbox].
class _AttachedImageThumbnail extends StatelessWidget {
  final Uint8List imageBytes;
  const _AttachedImageThumbnail({required this.imageBytes});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    // Designer BLOCKING: the bare GestureDetector announced nothing to a
    // screen reader. The tap target is already the full thumbnail (≥200px),
    // so the gap was purely semantic — a button role + label + tooltip.
    return Tooltip(
      message: 'View image',
      child: Semantics(
        button: true,
        label: 'View image',
        child: GestureDetector(
          key: const Key('attached-image-thumbnail'),
          onTap: () => showImageLightbox(context, imageBytes),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(tokens.radius.sm),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 240),
              child: Image.memory(imageBytes, fit: BoxFit.cover),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditAffordance extends StatelessWidget {
  final VoidCallback onEdit;
  const _EditAffordance({required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Opacity(
      opacity: 0.7,
      child: IconButton(
        onPressed: onEdit,
        tooltip: 'Edit message',
        icon: Icon(Icons.edit_outlined, size: 16, color: color),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(
          minWidth: kMinInteractiveDimension,
          minHeight: kMinInteractiveDimension,
        ),
      ),
    );
  }
}

class _MarkdownBody extends StatelessWidget {
  final String text;
  final Color onColor;
  const _MarkdownBody({required this.text, required this.onColor});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final textTheme = theme.textTheme;
    final styleSheet = MarkdownStyleSheet(
      p: textTheme.bodyLarge?.copyWith(color: onColor),
      h1: textTheme.titleMedium?.copyWith(color: onColor),
      h2: textTheme.titleSmall?.copyWith(color: onColor),
      h3: textTheme.titleSmall?.copyWith(color: onColor),
      h4: textTheme.titleSmall?.copyWith(color: onColor),
      h5: textTheme.titleSmall?.copyWith(color: onColor),
      h6: textTheme.titleSmall?.copyWith(color: onColor),
      strong: textTheme.bodyLarge?.copyWith(
        color: onColor,
        fontWeight: FontWeight.w700,
      ),
      em: textTheme.bodyLarge?.copyWith(
        color: onColor,
        fontStyle: FontStyle.italic,
      ),
      code: textTheme.bodyMedium?.copyWith(
        color: onColor,
        fontFamily: 'monospace',
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
      ),
      blockquote: textTheme.bodyLarge?.copyWith(
        color: onColor,
        fontStyle: FontStyle.italic,
      ),
      blockquotePadding: EdgeInsets.only(left: tokens.spacing.sm),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: theme.colorScheme.outline,
            width: tokens.spacing.xs,
          ),
        ),
      ),
      listBullet: textTheme.bodyLarge?.copyWith(color: onColor),
      listIndent: tokens.spacing.sm,
      a: textTheme.bodyLarge?.copyWith(
        color: theme.colorScheme.secondary,
        decoration: TextDecoration.underline,
      ),
      tableBody: textTheme.bodySmall?.copyWith(color: onColor),
      tableBorder: TableBorder.all(color: theme.colorScheme.outlineVariant),
      blockSpacing: tokens.spacing.sm,
    );
    return MarkdownBody(
      data: text,
      selectable: true,
      styleSheet: styleSheet,
      builders: {'pre': _CodeBlockBuilder(tokens: tokens, theme: theme)},
      // Security (F1): model text may be steered by untrusted sources, so
      // markdown never fetches an image, and a link opens only after the
      // user confirms the full URL (core/markdown/safe_markdown.dart).
      imageBuilder: safeMarkdownImageBuilder,
      onTapLink: (linkText, href, title) =>
          unawaited(confirmAndOpenMarkdownLink(context, href)),
    );
  }
}

/// chat-spec.md §2.3: full-width code well, language label, copy-to-
/// checkmark button (no snackbar — the icon swap is the confirmation).
class _CodeBlockBuilder extends MarkdownElementBuilder {
  final DhruvaTokens tokens;
  final ThemeData theme;
  _CodeBlockBuilder({required this.tokens, required this.theme});

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final codeElement = element.children?.whereType<md.Element>().firstOrNull;
    final classAttr = codeElement?.attributes['class'] ?? '';
    final language = classAttr.startsWith('language-')
        ? classAttr.substring('language-'.length)
        : null;
    var code = element.textContent;
    if (code.endsWith('\n')) code = code.substring(0, code.length - 1);
    return _CodeBlock(
      code: code,
      language: language,
      tokens: tokens,
      theme: theme,
    );
  }
}

class _CodeBlock extends StatefulWidget {
  final String code;
  final String? language;
  final DhruvaTokens tokens;
  final ThemeData theme;

  const _CodeBlock({
    required this.code,
    required this.language,
    required this.tokens,
    required this.theme,
  });

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(_copiedHold);
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final theme = widget.theme;
    final scheme = theme.colorScheme;
    final onVariant = scheme.onSurfaceVariant;
    final copyColor = _copied ? tokens.success : onVariant;
    // mk-code (mock.css): a bordered well on `surface`, a thin uppercase
    // header divided from the body, language label left + copy affordance
    // right. Corners clip the header's divider flush to the radius.
    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(vertical: tokens.spacing.xs),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(tokens.radius.sm),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                tokens.spacing.sm,
                tokens.spacing.xs,
                tokens.spacing.xs,
                tokens.spacing.xs,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    (widget.language ?? 'code').toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: onVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  Tooltip(
                    message: _copied ? 'Copied' : 'Copy code',
                    child: InkWell(
                      onTap: _copy,
                      borderRadius: BorderRadius.circular(tokens.radius.xs),
                      child: Padding(
                        padding: EdgeInsets.all(tokens.spacing.xs),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedSwitcher(
                              duration:
                                  tokens.motion.instant +
                                  const Duration(milliseconds: 20),
                              child: Icon(
                                _copied ? Icons.check : Icons.copy,
                                key: ValueKey(_copied),
                                size: 13,
                                color: copyColor,
                              ),
                            ),
                            SizedBox(width: tokens.spacing.xs),
                            Text(
                              _copied ? 'Copied' : 'Copy',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: copyColor,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(tokens.spacing.sm),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                widget.code,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface,
                  fontFamily: 'monospace',
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
