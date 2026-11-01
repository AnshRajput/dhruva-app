/// Today's brief card. Every state ends in something the user can do:
///
///  * loading: a skeleton, not a spinner
///  * calendar off: one tap "Connect your calendar (no sign-in)", and when the
///    OS said no, the fix in words with "Open settings"
///  * a written brief: cited phrases are tappable and open their source;
///    "How this was written" lists the numbered facts
///  * no brief yet (no model, model loading, or not written yet): the facts as
///    a plain list, which is still useful, plus "Write my brief" when a model
///    can do it
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/brand_star.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../data/connectors/connector.dart';
import '../state/brief_cache.dart';
import '../state/brief_controller.dart';
import '../state/brief_facts.dart';
import '../state/brief_parser.dart';
import '../state/brief_writer.dart';
import '../state/day_text.dart';
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
    final facts = ref.watch(briefFactsProvider);
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
    final bs = brief.value;
    if (bs == null) {
      return brief.hasError
          ? _FactsCard(facts: facts, state: null)
          : const _BriefSkeleton();
    }
    final written = bs.brief;
    if (written != null) {
      final parsed = written.parsed();
      if (!parsed.isEmpty) {
        return _WrittenCard(state: bs, brief: written, parsed: parsed);
      }
    }
    return _FactsCard(facts: facts, state: bs);
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

/// The written brief with tappable cited phrases.
class _WrittenCard extends ConsumerStatefulWidget {
  const _WrittenCard({
    required this.state,
    required this.brief,
    required this.parsed,
  });

  final BriefState state;
  final WrittenBrief brief;
  final ParsedBrief parsed;

  @override
  ConsumerState<_WrittenCard> createState() => _WrittenCardState();
}

class _WrittenCardState extends ConsumerState<_WrittenCard> {
  bool _open = false;

  void _openCites(List<int> cites) {
    final f = widget.brief.fact(cites.first);
    if (f != null) openFact(context, ref, f);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final scheme = theme.colorScheme;
    final now = ref.watch(nowProvider);
    final fresh = isBriefFresh(widget.brief, now);
    final at = formatClock(context, widget.brief.writtenAt);
    final busy = widget.state.writing;
    final reduce = MediaQuery.disableAnimationsOf(context);
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
              sentences: widget.parsed.sentences,
              onCite: _openCites,
            ),
          ),
          SizedBox(height: tokens.spacing.md),
          Row(
            children: [
              Icon(Icons.lock_outline, size: 14, color: tokens.success),
              SizedBox(width: tokens.spacing.xs),
              Expanded(
                child: Text(
                  busy
                      ? (widget.state.warming
                            ? 'Warming up your model…'
                            : 'Writing a new one…')
                      : fresh
                      ? 'Written on this phone at $at'
                      : 'Written on this phone at $at · ${ageLabel(widget.brief.writtenAt, now)}',
                  key: const ValueKey('today-brief-footer'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('today-brief-regenerate'),
                tooltip: 'Write it again',
                icon: const Icon(Icons.refresh_rounded, size: 20),
                onPressed: busy
                    ? null
                    : () => ref
                          .read(briefControllerProvider.notifier)
                          .regenerate(),
              ),
            ],
          ),
          if (widget.state.error != null) _ErrorLine(widget.state.error!),
          InkWell(
            key: const ValueKey('today-brief-how'),
            borderRadius: BorderRadius.circular(tokens.radius.sm),
            onTap: () => setState(() => _open = !_open),
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
                    turns: _open ? 0.5 : 0,
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
            child: _open
                ? _FactList(
                    key: const ValueKey('today-brief-facts'),
                    facts: widget.brief.facts,
                    intro:
                        'Rules picked these facts from your calendar and '
                        'notifications. The model on your phone only put '
                        'them into words.',
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// No written brief: the facts, plainly, and the way to get one written.
class _FactsCard extends ConsumerWidget {
  const _FactsCard({required this.facts, required this.state});
  final List<BriefFact> facts;
  final BriefState? state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final s = state;
    final model = s?.model ?? BriefModelStatus.none;
    final busy = s?.writing ?? false;
    final String? status = busy
        ? (s!.warming ? 'Warming up your model…' : 'Writing your brief…')
        : null;
    return TodayCard(
      cardKey: const ValueKey('today-brief'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(),
          SizedBox(height: tokens.spacing.md),
          Text('Your day, at a glance', style: theme.textTheme.titleLarge),
          SizedBox(height: tokens.spacing.sm),
          _FactList(key: const ValueKey('today-brief-facts'), facts: facts),
          SizedBox(height: tokens.spacing.base),
          if (status != null)
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: tokens.spacing.sm),
                Text(
                  status,
                  key: const ValueKey('today-brief-status'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            )
          else if (model == BriefModelStatus.none)
            _GetModel()
          else
            FilledButton(
              key: const ValueKey('today-brief-write'),
              onPressed: () =>
                  ref.read(briefControllerProvider.notifier).regenerate(),
              child: const Text('Write my brief'),
            ),
          if (s?.error != null) _ErrorLine(s!.error!),
        ],
      ),
    );
  }
}

class _GetModel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Add a model and your phone writes this as a short brief for you.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(height: tokens.spacing.sm),
        OutlinedButton(
          key: const ValueKey('today-brief-get-model'),
          onPressed: () => context.push('/settings/models'),
          child: const Text('Get a model'),
        ),
      ],
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
