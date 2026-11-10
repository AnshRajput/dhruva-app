/// Actions (`/actions`, formerly Workflows): one-tap text verbs (summarize, translate, rewrite,
/// ...) that small on-device models are good at. Pick one, supply text (type,
/// paste, or open a file), and Run hands the rendered prompt to
/// `/chat/new`, which opens a chat and auto-sends the user's text. The verb's
/// instruction rides in the chat's system prompt (`asys`), so the thread shows
/// the user's own words under an "Action: ..." label, never the template.
/// `?text=` (from the Android share sheet / text-selection menu / Inbox) prefills
/// the input; `?pkg=` / `?app=` name the app a message came from, so a drafted
/// reply can offer "Open in" the source app.
library;

import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/actions/action_prompt.dart';
import '../../../core/router/route_trust.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/bottom_inset.dart';
import '../../../core/widgets/dhruva_sheet.dart';
import '../data/workflow_catalog.dart';

/// What the sheet hands back on Run: the verb, the user's text and the option.
typedef WorkflowRun = ({Workflow workflow, String text, String option});

/// `/chat/new` for [run]: the user's text is the prompt, the instruction the
/// system layer.
String workflowChatLocation(
  WorkflowRun run, {
  String? sourcePackage,
  String? sourceApp,
}) {
  final text = run.text.trim();
  final capped = text.length > workflowInputLimit
      ? text.substring(0, workflowInputLimit)
      : text;
  return Uri(
    path: '/chat/new',
    queryParameters: {
      'prompt': capped,
      routeKeyParam: trustedRouteKey,
      'asys': actionSystemPrompt(
        title: run.workflow.title,
        instruction: workflowInstruction(run.workflow, run.option),
      ),
      if (sourcePackage != null && sourcePackage.isNotEmpty)
        'pkg': sourcePackage,
      if (sourceApp != null && sourceApp.isNotEmpty) 'app': sourceApp,
    },
  ).toString();
}

class WorkflowsScreen extends StatefulWidget {
  /// Text to prefill into whichever workflow the user picks.
  final String? initialText;

  /// Opens this workflow's sheet right away (`?id=` from the chat quick strip).
  final String? initialWorkflowId;

  /// The app the text came from (an Inbox notification), if any.
  final String? sourcePackage;
  final String? sourceApp;

  const WorkflowsScreen({
    super.key,
    this.initialText,
    this.initialWorkflowId,
    this.sourcePackage,
    this.sourceApp,
  });

  @override
  State<WorkflowsScreen> createState() => _WorkflowsScreenState();
}

class _WorkflowsScreenState extends State<WorkflowsScreen> {
  String? get initialText => widget.initialText;

  @override
  void initState() {
    super.initState();
    final id = widget.initialWorkflowId;
    if (id == null) return;
    final match = workflowCatalog.where((w) => w.id == id);
    if (match.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_open(context, match.first));
      });
    }
  }

  Future<void> _open(BuildContext context, Workflow workflow) async {
    final run = await showDhruvaSheet<WorkflowRun>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          WorkflowSheet(workflow: workflow, initialText: initialText ?? ''),
    );
    if (run != null && context.mounted) {
      unawaited(
        context.push(
          workflowChatLocation(
            run,
            sourcePackage: widget.sourcePackage,
            sourceApp: widget.sourceApp,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final shared = initialText?.trim() ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Actions')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          tokens.spacing.md,
          tokens.spacing.xs,
          tokens.spacing.md,
          tokens.spacing.xl,
        ).withBottomInset(context),
        children: [
          Text(
            shared.isEmpty
                ? 'Pick a task, add your text, and your phone does the rest.'
                : 'Text ready. Pick what to do with it.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (shared.isNotEmpty) ...[
            SizedBox(height: tokens.spacing.sm),
            _SharedPreview(text: shared),
          ],
          SizedBox(height: tokens.spacing.sm),
          const _PrivacyNote(),
          SizedBox(height: tokens.spacing.md),
          for (final w in workflowCatalog)
            _WorkflowRow(workflow: w, onTap: () => _open(context, w)),
        ],
      ),
    );
  }
}

class _SharedPreview extends StatelessWidget {
  final String text;
  const _SharedPreview({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Container(
      padding: EdgeInsets.all(tokens.spacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(tokens.radius.md),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}

class _WorkflowRow extends StatelessWidget {
  final Workflow workflow;
  final VoidCallback onTap;
  const _WorkflowRow({required this.workflow, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.spacing.sm),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(tokens.radius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(tokens.radius.md),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(tokens.spacing.md),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(tokens.radius.sm),
                  ),
                  child: Icon(
                    workflow.icon,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                ),
                SizedBox(width: tokens.spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(workflow.title, style: theme.textTheme.titleSmall),
                      SizedBox(height: tokens.spacing.xs / 2),
                      Text(
                        workflow.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Row(
      children: [
        Icon(
          Icons.lock_outline_rounded,
          size: 14,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        SizedBox(width: tokens.spacing.xs),
        Expanded(
          child: Text(
            'Runs on your phone. Nothing is uploaded.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Input sheet for one workflow. Pops with a [WorkflowRun] on Run.
class WorkflowSheet extends StatefulWidget {
  final Workflow workflow;
  final String initialText;

  const WorkflowSheet({
    super.key,
    required this.workflow,
    this.initialText = '',
  });

  @override
  State<WorkflowSheet> createState() => _WorkflowSheetState();
}

class _WorkflowSheetState extends State<WorkflowSheet> {
  late final TextEditingController _ctrl;
  late String _option;
  bool _trimmed = false;

  @override
  void initState() {
    super.initState();
    _trimmed = widget.initialText.length > workflowInputLimit;
    _ctrl = TextEditingController(text: _cap(widget.initialText));
    _option = widget.workflow.option?.defaultChoice ?? '';
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _cap(String s) =>
      s.length > workflowInputLimit ? s.substring(0, workflowInputLimit) : s;

  /// Replaces the field with [text], capped to the model-friendly limit and
  /// flagging the trim so the user knows part of their text was dropped.
  void _setText(String text) {
    setState(() {
      _trimmed = text.length > workflowInputLimit;
      _ctrl.text = _cap(text);
    });
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      _toast('Clipboard has no text.');
      return;
    }
    _setText(text);
  }

  Future<void> _openFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Text',
          extensions: ['txt', 'md', 'csv', 'json', 'log'],
        ),
      ],
    );
    if (file == null) return;
    try {
      _setText(await file.readAsString());
    } catch (_) {
      _toast("Couldn't read that file as text.");
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final w = widget.workflow;
    final option = w.option;
    final tooShort = tooShortFor(w, _ctrl.text);
    final canRun = _ctrl.text.trim().isNotEmpty && tooShort == null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          tokens.spacing.lg,
          0,
          tokens.spacing.lg,
          tokens.spacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(w.icon, size: 20, color: theme.colorScheme.primary),
                SizedBox(width: tokens.spacing.sm),
                Text(w.title, style: theme.textTheme.titleLarge),
              ],
            ),
            SizedBox(height: tokens.spacing.md),
            TextField(
              controller: _ctrl,
              onChanged: (_) => setState(() => _trimmed = false),
              minLines: 5,
              maxLines: 9,
              maxLength: workflowInputLimit,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              buildCounter:
                  (
                    _, {
                    required currentLength,
                    required isFocused,
                    maxLength,
                  }) => null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: w.inputHint),
            ),
            if (_trimmed) ...[
              SizedBox(height: tokens.spacing.xs),
              Text(
                'Trimmed to $workflowInputLimit characters to fit your model.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.warning,
                ),
              ),
            ],
            if (tooShort != null) ...[
              SizedBox(height: tokens.spacing.xs),
              Text(
                tooShort,
                key: const ValueKey('workflow-too-short'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.warning,
                ),
              ),
            ],
            SizedBox(height: tokens.spacing.sm),
            // Wrap: at a large font size the two buttons drop to two lines
            // instead of overflowing the sheet.
            Wrap(
              spacing: tokens.spacing.sm,
              runSpacing: tokens.spacing.sm,
              children: [
                OutlinedButton.icon(
                  onPressed: _paste,
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                  label: const Text('Paste'),
                ),
                OutlinedButton.icon(
                  onPressed: _openFile,
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: const Text('Open text file'),
                ),
              ],
            ),
            if (option != null) ...[
              SizedBox(height: tokens.spacing.md),
              Text(
                option.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: tokens.spacing.xs),
              Wrap(
                spacing: tokens.spacing.xs,
                children: [
                  for (final c in option.choices)
                    ChoiceChip(
                      label: Text(c),
                      selected: _option == c,
                      onSelected: (_) => setState(() => _option = c),
                    ),
                ],
              ),
            ],
            SizedBox(height: tokens.spacing.lg),
            FilledButton(
              onPressed: canRun
                  ? () => Navigator.pop<WorkflowRun>(context, (
                      workflow: w,
                      text: _ctrl.text,
                      option: _option,
                    ))
                  : null,
              child: const Text('Run'),
            ),
            SizedBox(height: tokens.spacing.sm),
            Text(
              'Runs on your phone. Nothing is uploaded.',
              textAlign: TextAlign.center,
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
