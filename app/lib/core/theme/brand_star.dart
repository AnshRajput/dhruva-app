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
