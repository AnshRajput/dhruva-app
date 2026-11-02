/// Today's brief card. Every state ends in something the user can do:
///
///  * loading: a skeleton, not a spinner
///  * calendar off: one tap "Connect your calendar (no sign-in)", and when the
///    OS said no, the fix in words with "Open settings"
///  * the brief: 3 to 5 sentences written by rules from the day's data, shown
///    instantly with no model; cited phrases are tappable and open the RIGHT
///    source; "How this was written" lists the numbered facts
///  * optional "Rewrite in my words" when a model is ready: shown only if it
///    passed the strict grounding check, otherwise "Kept the checked version"
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/model_download.dart';
import '../../../core/theme/brand_star.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/model_download_line.dart';
import '../../../data/connectors/connector.dart';
import '../state/brief_cache.dart';
import '../state/brief_compose.dart';
import '../state/brief_controller.dart';
import '../state/brief_facts.dart';
import '../state/brief_parser.dart';
import '../state/brief_writer.dart';
import '../state/today_data.dart';
import 'today_actions.dart';
import 'today_widgets.dart';

class BriefCard extends ConsumerStatefulWidget {
  const BriefCard({super.key});

  @override
  ConsumerState<BriefCard> createState() => _BriefCardState();
}

class _BriefCardState extends ConsumerState<BriefCard> {
  bool _connecting = false;

  Future<void> _connect() async {
    setState(() => _connecting = true);
    final status = await connectCalendar(ref);
    if (!mounted) return;
    setState(() => _connecting = false);
    if (status == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't reach your calendar. Try again in a moment."),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loaded = ref.watch(connectorsLoadedProvider);
    final calendar = ref.watch(calendarEntryProvider);
    final day = ref.watch(dayBriefProvider);
    final facts = day.facts;
    final brief = ref.watch(briefControllerProvider);

    if (!loaded) return const _BriefSkeleton();

    final state = calendar?.status.state;
    if (state == ConnectorState.permissionDenied) {
      return _ConnectCard(
        title: 'Calendar access is off',
        body:
            'Your brief is built from your calendar. Allow Calendar for this '
            'app in your phone settings, then come back.',
        actionLabel: 'Open settings',
        actionKey: const ValueKey('today-brief-open-settings'),
        onAction: () => openCalendarSettings(ref),
      );
    }
    if (facts.isEmpty && !(calendar?.status.isConnected ?? false)) {
      return _ConnectCard(
        title: 'Connect your calendar',
        body:
            'See your day here and get a short brief, written on this phone. '
            'It uses the calendar already on your phone: no sign-in, and '
            'nothing is uploaded.',
        actionLabel: _connecting ? 'Connecting…' : 'Connect your calendar',
        actionKey: const ValueKey('today-brief-connect'),
        onAction: _connecting ? null : _connect,
      );
    }
    // Connected but the first read of the calendar is still running: an empty
    // store is not an empty day, so wait rather than say anything.
    if (facts.isEmpty && calendar?.status.lastSyncAt == null) {
      return const _BriefSkeleton();
    }
    return _BriefBody(day: day, state: brief.value);
  }
}

class _BriefSkeleton extends StatelessWidget {
  const _BriefSkeleton();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    return Semantics(
      label: 'Loading your brief',
      child: TodayCard(
        cardKey: const ValueKey('today-brief'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonBar(width: 80, height: 12),
            SizedBox(height: tokens.spacing.base),
            const SkeletonBar(height: 18),
            SizedBox(height: tokens.spacing.sm),
            const SkeletonBar(height: 18),
            SizedBox(height: tokens.spacing.sm),
            const SkeletonBar(width: 180, height: 18),
          ],
        ),
      ),
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Row(
      children: [
        DhruvaStar(size: 12, color: theme.colorScheme.primary),
        SizedBox(width: tokens.spacing.sm),
        Text(
          'Your brief',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class _ConnectCard extends StatelessWidget {
  const _ConnectCard({
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.actionKey,
    required this.onAction,
  });

  final String title;
  final String body;
  final String actionLabel;
  final Key actionKey;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return TodayCard(
      cardKey: const ValueKey('today-brief'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(),
          SizedBox(height: tokens.spacing.md),
          Text(title, style: theme.textTheme.titleLarge),
          SizedBox(height: tokens.spacing.sm),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: tokens.spacing.base),
          FilledButton(
            key: actionKey,
            onPressed: onAction,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

/// The brief: rule-written sentences with tappable cited phrases, or the
/// model's checked rewording of them.
class _BriefBody extends ConsumerStatefulWidget {
  const _BriefBody({required this.day, required this.state});

  final DayBrief day;
  final BriefState? state;

  @override
  ConsumerState<_BriefBody> createState() => _BriefBodyState();
}

class _BriefBodyState extends ConsumerState<_BriefBody> {
  /// Null = automatic: closed.
  bool? _open;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;
    final now = ref.watch(nowProvider);
    final s = widget.state;
    final rewrite = shownRewrite(s?.rewrite, widget.day.facts, now);
    final sentences = rewrite == null
        ? widget.day.sentences
        : rewrite.parsed().sentences;
    final facts = widget.day.facts;
    final open = _open ?? false;
    final busy = s?.writing ?? false;
    final reduce = MediaQuery.disableAnimationsOf(context);

    void onCite(List<int> cites) {
      for (final f in facts) {
        if (f.n == cites.first) {
          openFact(context, ref, f);
          return;
        }
      }
    }

    final sources = _sourcesRead(
      calendar: ref.watch(calendarEntryProvider)?.status.isConnected ?? false,
      notifications:
          ref.watch(notificationsEntryProvider)?.status.isConnected ?? false,
    );
    final String footer = busy
        ? ((s?.warming ?? false)
              ? 'Warming up your model…'
              : 'Rewriting in your words…')
        : rewrite != null
        ? 'Reworded on this phone at ${formatClock(context, rewrite.writtenAt)}'
              ' · checked against your day'
        : 'Made on this phone from $sources';
    return TodayCard(
      cardKey: const ValueKey('today-brief'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(),
          SizedBox(height: tokens.spacing.md),
          Opacity(
            opacity: busy ? 0.6 : 1,
            child: CitedText(
              key: const ValueKey('today-brief-text'),
              sentences: sentences,
              onCite: onCite,
            ),
          ),
          SizedBox(height: tokens.spacing.md),
          Row(
            children: [
              Icon(Icons.lock_outline, size: 14, color: tokens.success),
              SizedBox(width: tokens.spacing.xs),
              Expanded(
                child: Text(
                  footer,
                  key: const ValueKey('today-brief-footer'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (s?.keptChecked ?? false) const _KeptLine(),
          if (s?.error != null) _ErrorLine(s!.error!),
          _RewriteRow(state: s, rewritten: rewrite != null, busy: busy),
          InkWell(
            key: const ValueKey('today-brief-how'),
            borderRadius: BorderRadius.circular(tokens.radius.sm),
            onTap: () => setState(() => _open = !open),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: tokens.spacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'How this was written',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: reduce ? Duration.zero : tokens.motion.fast,
                    curve: tokens.motion.decelerate,
                    child: Icon(
                      Icons.expand_more,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: reduce ? Duration.zero : tokens.motion.fast,
            curve: tokens.motion.decelerate,
            alignment: Alignment.topCenter,
            child: open
                ? _FactList(
                    key: const ValueKey('today-brief-facts'),
                    facts: facts,
                    intro: rewrite == null
                        ? 'Rules read $sources and '
                              'wrote this from the facts below. No model is '
                              'involved and nothing is guessed.'
                        : 'Rules picked these facts from $sources. '
                              'The model on your phone only '
                              'reworded them, and every sentence was checked '
                              'against them before it was shown.',
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// What the brief was actually made from, so the footer never claims a source
/// the user has not connected.
String _sourcesRead({required bool calendar, required bool notifications}) {
  if (calendar && notifications) return 'your calendar and notifications';
  if (calendar) return 'your calendar';
  if (notifications) return 'your notifications';
  return 'what is on your phone';
}

/// What the user can do about the wording: reword it (a model is ready), see
/// the download, add a model, or go back to the original.
class _RewriteRow extends ConsumerWidget {
  const _RewriteRow({
    required this.state,
    required this.rewritten,
    required this.busy,
  });

  final BriefState? state;
  final bool rewritten;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = state?.model ?? BriefModelStatus.none;
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    final ctl = ref.read(briefControllerProvider.notifier);
    if (busy) {
      return Padding(
        padding: EdgeInsets.only(top: tokens.spacing.sm),
        child: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (model == BriefModelStatus.none) {
      return _GetModel();
    }
    return Wrap(
      spacing: tokens.spacing.sm,
      children: [
        if (rewritten) ...[
          TextButton.icon(
            key: const ValueKey('today-brief-regenerate'),
            onPressed: ctl.rewrite,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Write it again'),
          ),
          TextButton(
            key: const ValueKey('today-brief-original'),
            onPressed: ctl.useOriginal,
            child: const Text('Show original'),
          ),
        ] else
          TextButton.icon(
            key: const ValueKey('today-brief-rewrite'),
            onPressed: ctl.rewrite,
            icon: const Icon(Icons.auto_awesome_outlined, size: 18),
            label: const Text('Rewrite in my words'),
          ),
      ],
    );
  }
}

/// The rewrite was thrown away because it did not match the day: said plainly,
/// not as an error.
class _KeptLine extends StatelessWidget {
  const _KeptLine();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Padding(
      padding: EdgeInsets.only(top: tokens.spacing.sm),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: 16, color: tokens.success),
          SizedBox(width: tokens.spacing.xs),
          Expanded(
            child: Text(
              'Kept the checked version',
              key: const ValueKey('today-brief-kept'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GetModel extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final download = ref.watch(modelDownloadProvider).value;
    if (download != null) {
      // A model is on its way: say so, instead of offering to get one.
      return Padding(
        padding: EdgeInsets.only(top: tokens.spacing.sm),
        child: Column(
          key: const ValueKey('today-brief-downloading'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ModelDownloadLine(progress: download),
            SizedBox(height: tokens.spacing.xs),
            Text(
              'Then you can have this reworded in your own words.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    return TextButton(
      key: const ValueKey('today-brief-get-model'),
      onPressed: () => context.push('/settings/models'),
      child: const Text('Get a model to reword it'),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Padding(
      padding: EdgeInsets.only(top: tokens.spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 16, color: theme.colorScheme.error),
          SizedBox(width: tokens.spacing.xs),
          Expanded(
            child: Text(
              message,
              key: const ValueKey('today-brief-error'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Numbered facts, each a tap target that opens its source.
class _FactList extends ConsumerWidget {
  const _FactList({super.key, required this.facts, this.intro});
  final List<BriefFact> facts;
  final String? intro;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (intro != null)
          Padding(
            padding: EdgeInsets.only(bottom: tokens.spacing.sm),
            child: Text(
              intro!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final f in facts)
          InkWell(
            key: ValueKey('fact-${f.n}'),
            borderRadius: BorderRadius.circular(tokens.radius.sm),
            onTap: () => openFact(context, ref, f),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: tokens.spacing.xs + 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '[${f.n}]',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(f.text, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The brief text. A cited span is underlined in the accent colour and opens
/// its fact on tap; it shows a tinted press state the moment the finger goes
/// down.
class CitedText extends StatefulWidget {
  const CitedText({super.key, required this.sentences, required this.onCite});

  final List<BriefSentence> sentences;
  final void Function(List<int> cites) onCite;

  @override
  State<CitedText> createState() => _CitedTextState();
}

class _CitedTextState extends State<CitedText> {
  // One recognizer per cited span, kept across rebuilds: the press highlight
  // rebuilds mid-gesture, and a recognizer replaced then would never tap.
  final _recognizers = <int, TapGestureRecognizer>{};
  int? _pressed;

  @override
  void dispose() {
    for (final r in _recognizers.values) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Brief text uses the display voice, like the comps.
    final base = theme.textTheme.titleLarge!.copyWith(
      color: scheme.onSurfaceVariant,
      height: 1.4,
    );
    var index = 0;
    final spans = <InlineSpan>[];
    for (final (si, s) in widget.sentences.indexed) {
      if (si > 0) spans.add(const TextSpan(text: ' '));
      for (final span in s.spans) {
        if (!span.isCited) {
          spans.add(TextSpan(text: span.text));
          continue;
        }
        final id = index++;
        final r = _recognizers.putIfAbsent(id, TapGestureRecognizer.new)
          ..onTapDown = ((_) => setState(() => _pressed = id))
          ..onTapCancel = (() => setState(() => _pressed = null))
          ..onTap = () {
            setState(() => _pressed = null);
            widget.onCite(span.cites);
          };
        spans.add(
          TextSpan(
            text: span.text,
            recognizer: r,
            semanticsLabel: span.text,
            style: TextStyle(
              color: scheme.onSurface,
              decoration: TextDecoration.underline,
              decorationColor: scheme.primary,
              decorationThickness: 2,
              backgroundColor: _pressed == id
                  ? scheme.primary.withValues(alpha: 0.18)
                  : null,
            ),
          ),
        );
      }
    }
    return Text.rich(TextSpan(style: base, children: spans));
  }
}
