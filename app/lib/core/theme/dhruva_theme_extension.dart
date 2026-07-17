/// Everything `ColorScheme`/`TextTheme` has no slot for: the success/warning
/// pair (not part of Material 3's scheme), the spacing/radius scales, the
/// elevation levels, and motion durations/easings — all straight from
/// `design-tokens.json`. Reach it via `Theme.of(context).extension<DhruvaTokens>()!`.
library;

import 'package:flutter/material.dart';

import 'design_tokens.dart';

@immutable
class DhruvaTokens extends ThemeExtension<DhruvaTokens> {
  final Color success;
  final Color onSuccess;
  final Color warning;
  final Color onWarning;
  final List<TokenElevationLevel> elevation;

  const DhruvaTokens({
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
    required this.elevation,
  });

  factory DhruvaTokens.fromColors(TokenColors colors) => DhruvaTokens(
    success: colors.success,
    onSuccess: colors.onSuccess,
    warning: colors.warning,
    onWarning: colors.onWarning,
    elevation: tokenElevation,
  );

  // Spacing/radius/motion are static numeric scales that don't vary by
  // brightness — exposed as instance getters here anyway so callers only
  // need one lookup (`Theme.of(context).extension<DhruvaTokens>()!`) for
  // every non-ColorScheme/TextTheme token.
  TokenSpacingScale get spacing => const TokenSpacingScale();
  TokenRadiusScale get radius => const TokenRadiusScale();
  TokenMotion get motion => const TokenMotion();

  @override
  DhruvaTokens copyWith({
    Color? success,
    Color? onSuccess,
    Color? warning,
    Color? onWarning,
    List<TokenElevationLevel>? elevation,
  }) => DhruvaTokens(
    success: success ?? this.success,
    onSuccess: onSuccess ?? this.onSuccess,
    warning: warning ?? this.warning,
    onWarning: onWarning ?? this.onWarning,
    elevation: elevation ?? this.elevation,
  );

  @override
  DhruvaTokens lerp(ThemeExtension<DhruvaTokens>? other, double t) {
    if (other is! DhruvaTokens) return this;
    return DhruvaTokens(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      // Elevation is a discrete scale, not a color — swap at the midpoint
      // instead of interpolating levels that don't have a numeric lerp.
      elevation: t < 0.5 ? elevation : other.elevation,
    );
  }
}

/// design-tokens.json `spacing` — logical pixels.
class TokenSpacingScale {
  const TokenSpacingScale();
  double get xs => TokenSpacing.xs;
  double get sm => TokenSpacing.sm;
  double get md => TokenSpacing.md;
  double get base => TokenSpacing.base;
  double get lg => TokenSpacing.lg;
  double get xl => TokenSpacing.xl;
  double get xl2 => TokenSpacing.xl2;
  double get xl3 => TokenSpacing.xl3;
  double get xl4 => TokenSpacing.xl4;
  double get xl5 => TokenSpacing.xl5;
  double get xl6 => TokenSpacing.xl6;
}

/// design-tokens.json `radius` — logical pixels; `full` is a pill (9999).
class TokenRadiusScale {
  const TokenRadiusScale();
  double get none => TokenRadius.none;
  double get xs => TokenRadius.xs;
  double get sm => TokenRadius.sm;
  double get md => TokenRadius.md;
  double get lg => TokenRadius.lg;
  double get xl => TokenRadius.xl;
  double get full => TokenRadius.full;
}

/// design-tokens.json `motion` — "settles rather than bounces": no
/// bounce/elastic/spring curves anywhere in the app.
class TokenMotion {
  const TokenMotion();
  Duration get instant => TokenMotionDuration.instant;
  Duration get fast => TokenMotionDuration.fast;
  Duration get base => TokenMotionDuration.base;
  Duration get moderate => TokenMotionDuration.moderate;
  Duration get slow => TokenMotionDuration.slow;
  Duration get slower => TokenMotionDuration.slower;
  Curve get standard => TokenMotionCurve.standard;
  Curve get decelerate => TokenMotionCurve.decelerate;
  Curve get accelerate => TokenMotionCurve.accelerate;
  Curve get emphasized => TokenMotionCurve.emphasized;
  Curve get linear => TokenMotionCurve.linear;
}
