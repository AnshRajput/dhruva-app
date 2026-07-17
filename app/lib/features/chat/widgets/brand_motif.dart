/// The brand's recurring 4-point star accent (design-tokens.json
/// `iconography.motif`) and the two places chat-spec.md names it directly:
/// the trust mark (§1.3) and the typing indicator (§3.3, replacing a
/// generic spinner — `iconography.avoid` bans those outright).
///
/// Hand-painted, not an icon-font glyph or SVG asset: no font/asset ships
/// this specific "elongated points, concave waists, open center pinhole"
/// shape (see `orchestra/research/brand-proposal.md`'s logo geometry), and
/// it's used in exactly three small, fixed sizes — a `CustomPainter` is
/// less code than sourcing/licensing/bundling an asset for one glyph.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/dhruva_theme_extension.dart';

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
      // Concave waist: the control point sits close to center, pulling the
      // curve inward instead of a straight diamond edge.
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

/// chat-spec.md §1.3 / §7.2: star glyph + "Runs 100% on your device",
/// present on every chat screen state. [style] defaults to `labelSmall`
/// (§1.3); the empty state (§7.2) passes `bodyMedium` for its larger scale.
class TrustMark extends StatelessWidget {
  final TextStyle? style;
  final double starSize;

  const TrustMark({super.key, this.style, this.starSize = 12});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final color = theme.colorScheme.onSurfaceVariant;
    final effectiveStyle = (style ?? theme.textTheme.labelSmall)?.copyWith(
      color: color,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DhruvaStar(size: starSize, color: color),
        SizedBox(width: tokens.spacing.xs),
        Text('Runs 100% on your device', style: effectiveStyle),
      ],
    );
  }
}

/// chat-spec.md §3.3: three star-motif dots pulsing in a staggered
/// sequence, fills the gap before the first `EngineToken` arrives.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  )..repeat();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = Theme.of(
      context,
    ).extension<DhruvaTokens>()!.motion.moderate;
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
    final color = theme.colorScheme.onSurfaceVariant;
    final curve = tokens.motion.emphasized;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) SizedBox(width: tokens.spacing.xs),
              Opacity(
                opacity: _pulseOpacity(curve, _controller.value, i),
                child: DhruvaStar(size: 6, color: color),
              ),
            ],
          ],
        );
      },
    );
  }

  double _pulseOpacity(Curve curve, double t, int index) {
    final shifted = (t + index / 3) % 1.0;
    final eased = curve.transform(shifted);
    return 0.25 + 0.75 * (1 - (2 * eased - 1).abs());
  }
}
