/// The brand's recurring 4-point star accent (design-tokens.json
/// `iconography.motif`), for consumers outside `features/chat` (which has
/// its own copy in `features/chat/widgets/brand_motif.dart` — the trust
/// mark + typing indicator built around it there are chat-specific, so
/// that file stays put rather than being uprooted for one new consumer).
///
/// ponytail: this duplicates `_StarPainter`'s geometry rather than having
/// `features/settings` import the chat feature's widget file — ADR-002
/// bans cross-feature imports, and this is a small (~35 line), stable,
/// design-system primitive, not business logic worth a bigger refactor
/// mid-loop. If a third feature needs it, promote `brand_motif.dart`'s
/// version to live here instead and re-export it from chat.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'design_tokens.dart';
import 'dhruva_theme_extension.dart';

/// One star glyph, [size] logical pixels square.
class DhruvaStar extends StatelessWidget {
  final double size;
  final Color color;

  const DhruvaStar({super.key, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _StarPainter(color: color),
    );
  }
}

class _StarPainter extends CustomPainter {
  final Color color;
  const _StarPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outer = size.shortestSide / 2;
    final waist = outer * 0.34;
    final pinhole = outer * 0.16;

    final path = Path();
    for (var i = 0; i < 4; i++) {
      final tipAngle = (math.pi / 2) * i - math.pi / 2;
      final tip =
          center + Offset(math.cos(tipAngle), math.sin(tipAngle)) * outer;
      final beforeAngle = tipAngle - math.pi / 4;
      final afterAngle = tipAngle + math.pi / 4;
      final before =
          center + Offset(math.cos(beforeAngle), math.sin(beforeAngle)) * waist;
      final after =
          center + Offset(math.cos(afterAngle), math.sin(afterAngle)) * waist;
      final controlIn = Offset.lerp(center, tip, 0.35)!;
      if (i == 0) path.moveTo(before.dx, before.dy);
      path
        ..quadraticBezierTo(controlIn.dx, controlIn.dy, tip.dx, tip.dy)
        ..quadraticBezierTo(controlIn.dx, controlIn.dy, after.dx, after.dy);
    }
    path.close();

    final hole = Path()
      ..addOval(Rect.fromCircle(center: center, radius: pinhole));
    final combined = Path.combine(PathOperation.difference, path, hole);
    canvas.drawPath(
      combined,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _StarPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// The app-wide loading indicator: the brand star, breathing.
///
/// `design-tokens.json iconography.avoid` bans generic circular spinners and
/// `iconography.motif` names the 4-point star as "the loading/thinking
/// indicator". The pole star is the fixed point that *never moves*
/// (`meta.story`), so this deliberately does NOT rotate — it pulses opacity
/// and scale on the calm `pulseSlow` breathing rate, easing in and out with a
/// sine so nothing overshoots (`motion.philosophy`). Use this everywhere a
/// bare `Center(child: CircularProgressIndicator())` used to sit; keep the
/// determinate download ring where real progress exists.
class DhruvaLoader extends StatefulWidget {
  /// Star size in logical pixels. Defaults to a page-loader scale; pass ~18
  /// for an inline/in-button loader.
  final double size;

  /// Defaults to the brand gold (`colorScheme.primary`). Override on colored
  /// surfaces (e.g. `onPrimary` inside a filled button).
  final Color? color;

  /// Optional label rendered under the star (`bodyMedium`, muted), for
  /// full-screen loading states that benefit from a word of reassurance.
  final String? label;

  const DhruvaLoader({super.key, this.size = 32, this.color, this.label});

  @override
  State<DhruvaLoader> createState() => _DhruvaLoaderState();
}

class _DhruvaLoaderState extends State<DhruvaLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: TokenMotionDuration.pulseSlow,
  )..repeat();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = Theme.of(
      context,
    ).extension<DhruvaTokens>()!.motion.pulseSlow;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final color = widget.color ?? theme.colorScheme.primary;
    final star = RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          // One smooth breath per cycle: sine gives an ease-in-out with no
          // hard edge at the loop seam (sin(0)==sin(2π)).
          final breath = 0.5 + 0.5 * math.sin(_controller.value * 2 * math.pi);
          return Opacity(
            opacity: 0.45 + 0.55 * breath,
            child: Transform.scale(scale: 0.9 + 0.1 * breath, child: child),
          );
        },
        child: DhruvaStar(size: widget.size, color: color),
      ),
    );
    if (widget.label == null) {
      return Semantics(label: 'Loading', child: star);
    }
    return Semantics(
      label: 'Loading',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          star,
          SizedBox(height: tokens.spacing.md),
          Text(
            widget.label!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
