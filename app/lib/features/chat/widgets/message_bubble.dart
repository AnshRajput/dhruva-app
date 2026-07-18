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
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../data/chat/chat_repository.dart';
import '../../vision/widgets/image_lightbox.dart';
import '../../voice/widgets/tts_button.dart';
import '../state/message_info_x.dart';
import 'reasoning_block.dart';

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

  const MessageBubble({
    super.key,
    required this.message,
    this.isStreaming = false,
    this.reasoningDurationMs,
    this.reasoningOpen = false,
    this.attachedImage,
    this.onRegenerate,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    if (message.role == MessageRole.system) {
      return _SystemBanner(message: message);
    }

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
            if (!isUser) ...[
              SizedBox(height: tokens.spacing.xs),
              _MetadataRow(message: message, onRegenerate: onRegenerate),
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

class _MetadataRow extends StatefulWidget {
  final MessageInfo message;
  final VoidCallback? onRegenerate;

  const _MetadataRow({required this.message, this.onRegenerate});

  @override
  State<_MetadataRow> createState() => _MetadataRowState();
}

class _MetadataRowState extends State<_MetadataRow> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.message.content));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_relativeTime(message.createdAt), style: style),
        if (tokPerSec != null) Text(' · $tokPerSec tok/s', style: style),
        if (message.content.isNotEmpty) ...[
          SizedBox(width: tokens.spacing.xs),
          TtsButton(messageId: message.id, text: message.content),
        ],
        // WS3: copy is a universal quick action on every assistant reply
        // with content — discoverable next to regenerate, not gated to the
        // vision "Extract text" preset it started life as (Loop 7).
        if (message.content.isNotEmpty) ...[
          SizedBox(width: tokens.spacing.xs),
          IconButton(
            onPressed: _copy,
            tooltip: _copied ? 'Copied' : 'Copy text',
            icon: Icon(
              _copied ? Icons.check : Icons.copy,
              size: 16,
              color: _copied ? tokens.success : color,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            visualDensity: VisualDensity.compact,
          ),
        ],
        if (onRegenerate != null) ...[
          SizedBox(width: tokens.spacing.xs),
          // Designer BLOCKING #2: a bare InkWell+Icon here was a ~16px hit
          // area with no tooltip/semantic label. IconButton gives both for
          // free (native widget, ladder rung 4) plus an explicit >=44px
          // tappable box without inflating the icon's visual size.
          IconButton(
            onPressed: onRegenerate,
            tooltip: 'Regenerate response',
            icon: Icon(Icons.refresh, size: 16, color: color),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            visualDensity: VisualDensity.compact,
          ),
        ],
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
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

String _relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
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
      // N4 (staff review): links were rendered underlined/styled as links
      // (the `a:` style above) but not actually tappable. External,
      // user-initiated per Rule 5 — no confirmation dialog (not asked
      // for), but the link's own underline+secondary-color styling is
      // what makes tapping it "obvious," and only http(s) hrefs are
      // honored (a model emitting a `javascript:`/`file:`/`intent:` href
      // is a trust-boundary case, not a legitimate link to open).
      onTapLink: (linkText, href, title) => _openMarkdownLink(href),
    );
  }
}

void _openMarkdownLink(String? href) {
  if (href == null) return;
  final uri = Uri.tryParse(href);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return;
  unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
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
    await Future<void>.delayed(widget.tokens.motion.moderate);
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
                            Icon(
                              _copied ? Icons.check : Icons.copy,
                              size: 13,
                              color: copyColor,
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
