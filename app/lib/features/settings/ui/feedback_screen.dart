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
          child: FilledButton(
            key: const ValueKey('feedback-send'),
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: s.busy ? null : c.send,
            child: Text(s.busy ? 'Opening…' : 'Open email draft'),
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
            child: _HandoffNote(handoff: s.handoff!),
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
            Wrap(
              spacing: tokens.spacing.sm,
              runSpacing: tokens.spacing.sm,
              children: [
                for (var i = 0; i < s.attachments.length; i++)
                  _Thumb(
                    a: s.attachments[i],
                    onRemove: () => c.removeAttachment(i),
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

class _Thumb extends StatelessWidget {
  const _Thumb({required this.a, required this.onRemove});

  final FeedbackAttachment a;
  final VoidCallback onRemove;

  static const _size = 72.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final radius = BorderRadius.circular(tokens.radius.md);
    return SizedBox(
      // The remove button is 48 dp and overhangs the corner.
      width: _size + 24,
      height: _size + 24,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            bottom: 0,
            child: ClipRRect(
              borderRadius: radius,
              child: SizedBox(
                width: _size,
                height: _size,
                child: a.isVideo
                    ? ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.videocam_outlined,
                          semanticLabel: 'Video ${a.name}',
                        ),
                      )
                    : Image.file(
                        File(a.path),
                        fit: BoxFit.cover,
                        cacheWidth: 192,
                        semanticLabel: 'Screenshot ${a.name}',
                        errorBuilder: (_, _, _) => ColoredBox(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.image_outlined),
                        ),
                      ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: IconButton.filledTonal(
              tooltip: 'Remove ${a.name}',
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              iconSize: 18,
              icon: const Icon(Icons.close),
              onPressed: onRemove,
            ),
          ),
        ],
      ),
    );
  }
}

class _HandoffNote extends StatelessWidget {
  const _HandoffNote({required this.handoff});
  final FeedbackHandoff handoff;

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
            if (viaShare) ...[
              SizedBox(height: tokens.spacing.xs),
              Text(
                'No email app is set up on this phone, so we opened the share '
                'sheet instead. Send it to $developerEmail.',
                style: theme.textTheme.bodyMedium,
              ),
              TextButton.icon(
                key: const ValueKey('feedback-copy-address'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy email address'),
                onPressed: () async {
                  await Clipboard.setData(
                    const ClipboardData(text: developerEmail),
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Address copied.')),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
