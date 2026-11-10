/// Settings > Help us improve: report a bug / request a feature. The result is
/// an email DRAFT in the user's own mail app (or the share sheet when there is
/// none). The app sends nothing and says so. Rendering only: the logic is in
/// `feedback_controller.dart` and `core/feedback`.
library;

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/crash/crash_log.dart';
import '../../../core/feedback/feedback_report.dart';
import '../../../core/feedback/feedback_sender.dart';
import '../../../core/safety/report_mail.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/platform_chrome.dart' show isCupertinoChrome;
import '../state/feedback_controller.dart';
import '../widgets/settings_widgets.dart';

class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({
    super.key,
    this.entry = (type: FeedbackType.bug, fromCrash: false),
  });

  final FeedbackEntry entry;

  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _steps = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _steps.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final provider = feedbackFormProvider(widget.entry);
    final s = ref.watch(provider);
    final c = ref.read(provider.notifier);
    // A saved draft was loaded (Android reclaimed us while the mail app was
    // up, or the user came back later): show it in the fields.
    ref.listen(provider.select((s) => s.restoreSeq), (_, _) {
      final r = ref.read(provider);
      _title.text = r.title;
      _description.text = r.description;
      _steps.text = r.steps;
    });
    final pad = EdgeInsets.symmetric(horizontal: tokens.spacing.base);
    final gap = SizedBox(height: tokens.spacing.base);

    return SettingsPage(
      title: 'Help us improve',
      subtitle:
          'Your note opens as a draft in your email app. Nothing is sent '
          'until you send it there.',
      children: [
        Padding(
          padding: pad,
          child: _TypeToggle(value: s.type, onChanged: c.setType),
        ),
        gap,
        Padding(
          padding: pad,
          child: TextField(
            key: const ValueKey('feedback-title'),
            controller: _title,
            onChanged: c.setTitle,
            maxLength: feedbackTitleMax,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Title',
              errorText: s.titleError,
            ),
          ),
        ),
        gap,
        Padding(
          padding: pad,
          child: TextField(
            key: const ValueKey('feedback-description'),
            controller: _description,
            onChanged: c.setDescription,
            minLines: 4,
            maxLines: 10,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: s.type.descriptionPrompt,
              alignLabelWithHint: true,
              errorText: s.descriptionError,
            ),
          ),
        ),
        if (s.type == FeedbackType.bug) ...[
          gap,
          Padding(
            padding: pad,
            child: TextField(
              key: const ValueKey('feedback-steps'),
              controller: _steps,
              onChanged: c.setSteps,
              minLines: 2,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Steps to reproduce (optional)',
                alignLabelWithHint: true,
              ),
            ),
          ),
        ],
        const SettingsSectionLabel('Screenshots or a short video'),
        _Attachments(entry: widget.entry),
        const SettingsSectionLabel('What to include'),
        SettingsGroup(
          children: [
            CheckboxListTile.adaptive(
              key: const ValueKey('feedback-device'),
              value: s.includeDevice,
              onChanged: (v) => c.setIncludeDevice(v ?? false),
              title: const Text('Include device info'),
              subtitle: const Text(
                'Phone model, OS version, app version and build, installed '
                'model names and sizes, free RAM and storage.',
              ),
            ),
            _CrashCheckbox(entry: widget.entry),
          ],
        ),
        SettingsNote(ref.watch(feedbackPreviewProvider(widget.entry))),
        SettingsNote(feedbackNeverIncluded),
        gap,
        Padding(
          padding: pad,
          // Both ways out are always offered: Android cannot tell us whether
          // a mail account is set up (a signed-out Gmail opens a welcome
          // tour), so the share sheet is never hidden behind a failure.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                key: const ValueKey('feedback-send'),
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: s.busy ? null : c.send,
                child: Text(s.busy ? 'Opening…' : 'Open email draft'),
              ),
              SizedBox(height: tokens.spacing.sm),
              OutlinedButton(
                key: const ValueKey('feedback-share'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
                onPressed: s.busy ? null : c.share,
                child: const Text('Share another way'),
              ),
              TextButton.icon(
                key: const ValueKey('feedback-copy-address'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy email address'),
                onPressed: () => _copyAddress(context),
              ),
            ],
          ),
        ),
        if (s.sendError != null) SettingsNote(s.sendError!),
        if (s.handoff != null)
          Padding(
            padding: EdgeInsets.fromLTRB(
              tokens.spacing.base,
              tokens.spacing.base,
              tokens.spacing.base,
              0,
            ),
            child: _HandoffNote(
              entry: widget.entry,
              handoff: s.handoff!,
              onShare: c.share,
              onDone: () async {
                await c.finish();
                if (context.mounted) await Navigator.of(context).maybePop();
              },
            ),
          ),
      ],
    );
  }
}

/// Bug / Feature: M3 pill segmented button on Android, iOS segmented control
/// on iOS (Rule 6). Both are 48 dp tall.
class _TypeToggle extends StatelessWidget {
  const _TypeToggle({required this.value, required this.onChanged});

  final FeedbackType value;
  final ValueChanged<FeedbackType> onChanged;

  @override
  Widget build(BuildContext context) {
    if (isCupertinoChrome(context)) {
      return CupertinoSlidingSegmentedControl<FeedbackType>(
        key: const ValueKey('feedback-type'),
        groupValue: value,
        onValueChanged: (v) {
          if (v != null) onChanged(v);
        },
        children: {
          for (final t in FeedbackType.values)
            t: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Text(t.label),
            ),
        },
      );
    }
    return SegmentedButton<FeedbackType>(
      key: const ValueKey('feedback-type'),
      showSelectedIcon: false,
      style: const ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(48, 48)),
      ),
      segments: [
        for (final t in FeedbackType.values)
          ButtonSegment(value: t, label: Text(t.label)),
      ],
      selected: {value},
      onSelectionChanged: (v) => onChanged(v.first),
    );
  }
}

class _CrashCheckbox extends ConsumerWidget {
  const _CrashCheckbox({required this.entry});
  final FeedbackEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(feedbackFormProvider(entry));
    final has = ref.watch(crashReportsProvider).value?.isNotEmpty ?? false;
    return CheckboxListTile.adaptive(
      key: const ValueKey('feedback-crash'),
      value: s.includeCrash,
      onChanged: has || s.includeCrash
          ? (v) => ref
                .read(feedbackFormProvider(entry).notifier)
                .setIncludeCrash(v ?? false)
          : null,
      title: const Text('Include recent crash log'),
      subtitle: Text(
        has
            ? 'Error types and stack traces only, as in Crash reports. '
                  'Attached as $feedbackCrashLogFileName.'
            : 'No crash has been recorded on this phone.',
      ),
    );
  }
}

class _Attachments extends ConsumerWidget {
  const _Attachments({required this.entry});
  final FeedbackEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final s = ref.watch(feedbackFormProvider(entry));
    final c = ref.read(feedbackFormProvider(entry).notifier);
    final total = s.attachments.fold<int>(0, (a, e) => a + e.bytes);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (s.attachments.isNotEmpty)
            Column(
              children: [
                for (var i = 0; i < s.attachments.length; i++)
                  Padding(
                    padding: EdgeInsets.only(bottom: tokens.spacing.xs),
                    child: _AttachmentRow(
                      a: s.attachments[i],
                      onRemove: () => c.removeAttachment(i),
                    ),
                  ),
              ],
            ),
          if (s.attachments.isNotEmpty) SizedBox(height: tokens.spacing.sm),
          OutlinedButton.icon(
            key: const ValueKey('feedback-add-media'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: c.addMedia,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Add screenshots or a short video'),
          ),
          Padding(
            padding: EdgeInsets.only(top: tokens.spacing.xs),
            child: Text(
              s.attachError ??
                  'Up to $feedbackMaxAttachments files, '
                      '${feedbackMaxAttachmentBytes ~/ (1024 * 1024)} MB '
                      'together'
                      '${s.attachments.isEmpty ? '' : ' (${formatFeedbackBytes(total)} used)'}.',
              key: const ValueKey('feedback-attach-note'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: s.attachError != null
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One attachment: a 56 dp thumbnail (with an immediate placeholder, since
/// large photos take a moment to decode), its name and size, and a 48 dp
/// remove button on its own, clear of the image.
class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({required this.a, required this.onRemove});

  final FeedbackAttachment a;
  final VoidCallback onRemove;

  static const _size = 56.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final placeholder = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          a.isVideo ? Icons.videocam_outlined : Icons.image_outlined,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(tokens.radius.md),
          child: SizedBox(
            width: _size,
            height: _size,
            child: a.isVideo
                ? placeholder
                : Image.file(
                    File(a.path),
                    fit: BoxFit.cover,
                    cacheWidth: 168,
                    // Shown until the first decoded frame, so the row never
                    // appears as just a remove button.
                    frameBuilder: (_, child, frame, sync) =>
                        sync || frame != null ? child : placeholder,
                    errorBuilder: (_, _, _) => placeholder,
                  ),
          ),
        ),
        SizedBox(width: tokens.spacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                formatFeedbackBytes(a.bytes),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('feedback-remove'),
          tooltip: 'Remove attachment',
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          icon: const Icon(Icons.close),
          onPressed: onRemove,
        ),
      ],
    );
  }
}

Future<void> _copyAddress(BuildContext context) async {
  await Clipboard.setData(const ClipboardData(text: developerEmail));
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('Address copied.')));
}

class _HandoffNote extends StatelessWidget {
  const _HandoffNote({
    required this.entry,
    required this.handoff,
    required this.onShare,
    required this.onDone,
  });

  final FeedbackEntry entry;
  final FeedbackHandoff handoff;
  final VoidCallback onShare;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final viaShare = handoff == FeedbackHandoff.shareSheet;
    return Container(
      key: const ValueKey('feedback-handoff'),
      padding: EdgeInsets.all(tokens.spacing.base),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(tokens.radius.lg),
      ),
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Thanks. Send it from your email app to reach us.',
              style: theme.textTheme.titleSmall,
            ),
            SizedBox(height: tokens.spacing.xs),
            Text(
              viaShare
                  ? 'Pick an app in the share sheet and send it to '
                        '$developerEmail.'
                  : 'Your draft is saved here until you tap Done.',
              style: theme.textTheme.bodyMedium,
            ),
            if (!viaShare)
              TextButton(
                key: const ValueKey('feedback-share-recovery'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: onShare,
                child: const Text("Didn't open a draft? Share another way"),
              ),
            TextButton(
              key: const ValueKey('feedback-done'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: onDone,
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
