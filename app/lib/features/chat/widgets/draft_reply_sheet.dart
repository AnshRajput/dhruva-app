/// The Draft reply result (comp `thread-draft.png`): an EDITABLE draft in a
/// sheet, tone chips (Short / Warm / Formal) that rewrite it, Copy, Share,
/// "Open in <source app>" and Save. Never sends anything: every action is a tap
/// and the user owns the text.
///
/// It sits on the Draft reply chat (an Action chat, see
/// `core/actions/action_prompt.dart`): a tone chip sets that chat's system
/// prompt to the new tone and regenerates through the normal chat controller
/// (the one engine path), then the new reply fills the field. "Didn't cover"
/// is a rule check of the original message's questions and requests against
/// the draft, so a draft that skipped an ask says so honestly.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/actions/action_prompt.dart';
import '../../../core/di/connector_providers.dart' show externalOpenerProvider;
import '../../../core/di/library_providers.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/dhruva_sheet.dart';
import '../../../data/chat/chat_repository.dart';
import '../../../data/connectors/ask_sources.dart' show AskSource, AskSourceX;
import '../state/ask_selection.dart';
import '../state/chat_controller.dart';
import '../state/message_info_x.dart';

/// The text of the newest finished assistant reply, or null.
MessageInfo? latestReply(ChatThreadState s) {
  for (final m in s.visibleMessages.reversed) {
    if (m.role == MessageRole.assistant &&
        m.status != MessageStatus.error &&
        m.id != s.streamingMessageId) {
      return m;
    }
  }
  return null;
}

/// The original message the draft answers: the first user turn.
String originalMessageOf(ChatThreadState s) {
  for (final m in s.visibleMessages) {
    if (m.role == MessageRole.user) return m.content;
  }
  return '';
}

Future<void> showDraftReplySheet(BuildContext context, ChatRouteArgs args) =>
    showDhruvaSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => DraftReplySheet(args: args),
    );

class DraftReplySheet extends ConsumerStatefulWidget {
  const DraftReplySheet({super.key, required this.args});
  final ChatRouteArgs args;

  @override
  ConsumerState<DraftReplySheet> createState() => _DraftReplySheetState();
}

class _DraftReplySheetState extends ConsumerState<DraftReplySheet> {
  late final TextEditingController _ctrl;
  late String _tone;
  late String _generated;
  bool _rewriting = false;

  ChatController get _controller =>
      ref.read(chatControllerProvider(widget.args).notifier);

  @override
  void initState() {
    super.initState();
    final s = ref.read(chatControllerProvider(widget.args)).value;
    _ctrl = TextEditingController(
      text: s == null ? '' : (latestReply(s)?.content ?? ''),
    );
    _generated = _ctrl.text;
    _tone = s == null ? 'Warm' : draftToneOf(s.systemPrompt);
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _rewrite(String tone) async {
    final s = ref.read(chatControllerProvider(widget.args)).value;
    final reply = s == null ? null : latestReply(s);
    if (s == null || reply == null || s.isGenerating || _rewriting) return;
    setState(() {
      _tone = tone;
      _rewriting = true;
    });
    await _controller.setSystemPrompt(draftReplySystemPrompt(tone));
    // Returns when the new reply is done (or failed): then it fills the field.
    await _controller.regenerate(reply.id);
    if (!mounted) return;
    final now = ref.read(chatControllerProvider(widget.args)).value;
    final fresh = now == null ? null : latestReply(now);
    // A rewrite that failed (or echoed the instruction) leaves the draft as
    // it was; it never fills the field with anything but a finished reply.
    final failed =
        now != null &&
        now.visibleMessages
                .lastWhere(
                  (m) => m.role == MessageRole.assistant,
                  orElse: () => reply,
                )
                .status ==
            MessageStatus.error;
    if (failed) _toast("That didn't work. Try again.");
    setState(() {
      _rewriting = false;
      if (!failed && fresh != null && fresh.content.trim().isNotEmpty) {
        _ctrl.text = fresh.content.trim();
        _generated = _ctrl.text;
      }
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _ctrl.text));
    _toast('Draft copied.');
  }

  Future<void> _share() =>
      SharePlus.instance.share(ShareParams(text: _ctrl.text));

  Future<void> _openSource() async {
    final pkg = widget.args.sourcePackage;
    final app = widget.args.sourceApp ?? 'the app';
    if (pkg == null || pkg.isEmpty) return;
    // Copy first: the user pastes the draft into the reply box there.
    await Clipboard.setData(ClipboardData(text: _ctrl.text));
    final ok = await ref.read(externalOpenerProvider).launchApp(pkg);
    _toast(
      ok
          ? 'Draft copied. Paste it in $app.'
          : 'Could not open $app. Your draft is copied.',
    );
  }

  Future<void> _save() async {
    final id = ref
        .read(chatControllerProvider(widget.args))
        .value
        ?.conversationId;
    await ref
        .read(libraryStoreProvider)
        .saveAnswer(_ctrl.text, conversationId: id);
    _toast('Saved to Library.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;
    final thread = ref.watch(chatControllerProvider(widget.args)).value;
    final source = thread == null ? '' : originalMessageOf(thread);
    final note = _rewriting ? null : omissionNote(source, _ctrl.text);
    final invented = _rewriting
        ? const <DraftInvention>[]
        : draftInventions(
            _ctrl.text,
            source,
            userEdits: userEditsOf(_generated, _ctrl.text),
          );
    final words = _ctrl.text.trim().isEmpty
        ? 0
        : _ctrl.text.trim().split(RegExp(r'\s+')).length;
    final app = widget.args.sourceApp;
    final canOpen =
        (widget.args.sourcePackage ?? '').isNotEmpty && _ctrl.text.isNotEmpty;
    final empty = _ctrl.text.trim().isEmpty;
    final selection = ref.watch(askSelectionProvider(widget.args)).selection;
    final pinned = selection.auto
        ? const <String>[]
        : [
            for (final s in AskSource.values)
              if (selection.pinned.contains(s)) s.label,
          ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        key: const ValueKey('draft-sheet'),
        padding: EdgeInsets.fromLTRB(
          tokens.spacing.lg,
          0,
          tokens.spacing.lg,
          tokens.spacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Draft reply',
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            SizedBox(height: tokens.spacing.sm),
            Wrap(
              spacing: tokens.spacing.sm,
              runSpacing: tokens.spacing.xs,
              children: [
                for (final t in draftTones)
                  ChoiceChip(
                    key: ValueKey('draft-tone-$t'),
                    label: Text(t),
                    selected: _tone == t,
                    onSelected: _rewriting
                        ? null
                        : (_) => unawaited(_rewrite(t)),
                  ),
              ],
            ),
            SizedBox(height: tokens.spacing.md),
            TextField(
              key: const ValueKey('draft-field'),
              controller: _ctrl,
              enabled: !_rewriting,
              minLines: 5,
              maxLines: 12,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: _rewriting ? 'Rewriting on this phone...' : null,
              ),
            ),
            SizedBox(height: tokens.spacing.xs),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _rewriting
                        ? 'Rewriting, on this phone'
                        : '$words words · written on this phone',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('draft-regenerate'),
                  tooltip: 'Write another version',
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _rewriting
                      ? null
                      : () => unawaited(_rewrite(_tone)),
                ),
              ],
            ),
            if (note != null)
              Padding(
                padding: EdgeInsets.only(bottom: tokens.spacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, size: 18, color: tokens.warning),
                    SizedBox(width: tokens.spacing.sm),
                    Expanded(
                      child: Text(
                        note,
                        key: const ValueKey('draft-omissions'),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            for (final i in invented)
              Padding(
                padding: EdgeInsets.only(bottom: tokens.spacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber, size: 18, color: tokens.warning),
                    SizedBox(width: tokens.spacing.sm),
                    Expanded(
                      child: Text(
                        i.warning,
                        key: ValueKey('draft-invention-${i.name}'),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            FilledButton.icon(
              key: const ValueKey('draft-copy'),
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy'),
              onPressed: empty || _rewriting ? null : () => unawaited(_copy()),
            ),
            SizedBox(height: tokens.spacing.sm),
            Wrap(
              spacing: tokens.spacing.sm,
              runSpacing: tokens.spacing.sm,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('draft-share'),
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('Share'),
                  onPressed: empty || _rewriting
                      ? null
                      : () => unawaited(_share()),
                ),
                if (canOpen)
                  OutlinedButton.icon(
                    key: const ValueKey('draft-open-source'),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(openAppLabel(app)),
                    onPressed: _rewriting
                        ? null
                        : () => unawaited(_openSource()),
                  ),
                OutlinedButton.icon(
                  key: const ValueKey('draft-save'),
                  icon: const Icon(Icons.bookmark_border_rounded, size: 18),
                  label: const Text('Save'),
                  onPressed: empty || _rewriting
                      ? null
                      : () => unawaited(_save()),
                ),
              ],
            ),
            SizedBox(height: tokens.spacing.sm),
            Text(
              'Nothing is sent. You edit it, then send it yourself.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            // N1: the draft reads your calendar, files or contacts only when
            // you pinned them; otherwise it is written from the message alone.
            Text(
              key: const ValueKey('draft-sources-note'),
              pinned.isEmpty
                  ? 'Written from this message only.'
                  : 'Also uses your ${pinned.join(', ')}, which you chose.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
