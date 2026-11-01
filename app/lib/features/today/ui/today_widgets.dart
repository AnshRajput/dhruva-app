/// Small shared pieces of the Today surfaces: section header, avatars, a
/// loading skeleton, the status chip and locale-aware time text.
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../data/connectors/connector.dart';
import '../state/brief_facts.dart';

/// "9:30" or "9:30 AM" per the phone's clock setting.
String formatClock(BuildContext context, DateTime t) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(t),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

/// "9:30 - 10:15" for a timed event, "All day" otherwise.
String formatRange(BuildContext context, ConnectorItem e) {
  if (isAllDay(e) || e.startsAt == null) return 'All day';
  final end = eventEnd(e);
  final start = formatClock(context, e.startsAt!);
  return end == null ? start : '$start – ${formatClock(context, end)}';
}

/// Section title with an optional trailing text action ("See day").
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.actionLabel,
    this.onAction,
    this.actionKey,
  });

  final String title;

  /// Quiet right-aligned text ("3 waiting").
  final String? trailing;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Row(
        children: [
          Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
          if (trailing != null)
            Text(
              trailing!,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (actionLabel != null)
            TextButton(
              key: actionKey,
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// One person as a circle: contact photo when the contacts connector has one,
/// else their initial on a token container colour.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.name,
    this.photoBase64,
    this.size = 32,
    this.colorIndex = 0,
  });

  final String name;
  final String? photoBase64;
  final double size;
  final int colorIndex;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (colorIndex % 3) {
      0 => (scheme.primaryContainer, scheme.onPrimaryContainer),
      1 => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      _ => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
    };
    final initial = name.trim().isEmpty
        ? '?'
        : String.fromCharCode(name.trim().runes.first).toUpperCase();
    Widget? photo;
    if (photoBase64 != null) {
      try {
        photo = Image.memory(
          base64Decode(photoBase64!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        );
      } on FormatException {
        photo = null;
      }
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        // A ring in the card colour separates overlapping avatars.
        border: Border.all(color: scheme.surface, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child:
          photo ??
          Text(
            initial,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
    );
  }
}

/// A person for [AvatarStack]: display name + optional photo.
final class Attendee {
  const Attendee(this.name, this.photoBase64);
  final String name;
  final String? photoBase64;
}

/// Attendees of [e], resolved through the contacts directory (lowercase email
/// to contact item) for names and photos.
List<Attendee> attendeesOf(
  ConnectorItem e,
  Map<String, ConnectorItem> contacts,
) {
  final out = <Attendee>[];
  final seen = <String>{};
  for (final p in e.people) {
    final c = p.email == null ? null : contacts[p.email!.toLowerCase()];
    final name = (c?.title.isNotEmpty ?? false)
        ? c!.title
        : (p.name?.trim().isNotEmpty ?? false)
        ? p.name!.trim()
        : (p.email?.split('@').first ?? '');
    if (name.isEmpty || !seen.add(name)) continue;
    final photo = c?.flags['photo'];
    out.add(Attendee(name, photo is String ? photo : null));
  }
  return out;
}

/// The names of [names] on ONE line that never cuts a name in half: as many
/// whole names as fit, then "+N" for the rest ("Ravi, Sana +2"). The first name
/// always shows; only when it alone is wider than the line does it ellipsize.
class AttendeeLine extends StatelessWidget {
  const AttendeeLine({super.key, required this.names, this.style});

  final List<String> names;
  final TextStyle? style;

  /// What [names] reads as in [maxWidth]; pure over the measuring function so
  /// it is testable without a render tree.
  static String fit(
    List<String> names,
    double maxWidth,
    double Function(String) measure,
  ) {
    if (names.isEmpty) return '';
    for (var k = names.length; k > 1; k--) {
      final text =
          '${names.take(k).join(', ')}${k < names.length ? ' +${names.length - k}' : ''}';
      if (measure(text) <= maxWidth) return text;
    }
    return names.length == 1
        ? names.first
        : '${names.first} +${names.length - 1}';
  }

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    final dir = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        double measure(String t) {
          final tp = TextPainter(
            text: TextSpan(text: t, style: base),
            textDirection: dir,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final w = tp.width;
          tp.dispose();
          return w;
        }

        return Text(
          fit(names, c.maxWidth, measure),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );
      },
    );
  }
}

/// Overlapping avatar circles, "+N" past [max].
class AvatarStack extends StatelessWidget {
  const AvatarStack({
    super.key,
    required this.people,
    this.max = 3,
    this.size = 32,
  });

  final List<Attendee> people;
  final int max;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const SizedBox.shrink();
    final shown = people.take(max).toList();
    final extra = people.length - shown.length;
    final overlap = size * 0.28;
    final theme = Theme.of(context);
    return ExcludeSemantics(
      child: SizedBox(
        height: size,
        width:
            shown.length * (size - overlap) +
            overlap +
            (extra > 0 ? size * 0.9 : 0),
        child: Stack(
          children: [
            for (var i = 0; i < shown.length; i++)
              Positioned(
                left: i * (size - overlap),
                child: PersonAvatar(
                  name: shown[i].name,
                  photoBase64: shown[i].photoBase64,
                  size: size,
                  colorIndex: i,
                ),
              ),
            if (extra > 0)
              Positioned(
                left: shown.length * (size - overlap) + overlap,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Text(
                    '+$extra',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A rounded grey bar standing in for text while data loads. Static on
/// purpose: no looping animation to fight reduced-motion or tests.
class SkeletonBar extends StatelessWidget {
  const SkeletonBar({super.key, this.width, this.height = 14});
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(tokens.radius.full),
      ),
    );
  }
}

/// The card surface every Today section sits on.
class TodayCard extends StatelessWidget {
  const TodayCard({super.key, required this.child, this.padding, this.cardKey});
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Key? cardKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return DecoratedBox(
      key: cardKey,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(tokens.radius.xl),
      ),
      child: Padding(
        padding: padding ?? EdgeInsets.all(tokens.spacing.lg),
        child: child,
      ),
    );
  }
}

/// Small coloured pill ("in 1h 48m", app chip).
class InfoPill extends StatelessWidget {
  const InfoPill(this.label, {super.key, this.pillKey});
  final String label;
  final Key? pillKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return DecoratedBox(
      key: pillKey,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(tokens.radius.full),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.md,
          vertical: tokens.spacing.xs,
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}
