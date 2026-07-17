/// Hand-transcribed mirror of `design-tokens.json` (repo root, canonical
/// brand source per ADR-003). Every value below must equal the JSON exactly
/// — enforced by `test/core/theme/app_theme_test.dart`, which parses the
/// JSON directly at test time and asserts equality against the `ThemeData`
/// these tokens build. If a token changes, edit the JSON first, then mirror
/// the change here; the test fails loudly on drift either way.
library;

import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show Cubic, Curve, Curves;

// ---------------------------------------------------------------------------
// Color — one full role set per mode (color.dark / color.light in the JSON).
// ---------------------------------------------------------------------------

class TokenColors {
  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  final Color tertiary;
  final Color onTertiary;
  final Color tertiaryContainer;
  final Color onTertiaryContainer;
  final Color surface;
  final Color onSurface;
  final Color surfaceVariant;
  final Color onSurfaceVariant;
  final Color surfaceTint;
  final Color background;
  final Color onBackground;
  final Color error;
  final Color onError;
  final Color errorContainer;
  final Color onErrorContainer;
  final Color success;
  final Color onSuccess;
  final Color warning;
  final Color onWarning;
  final Color outline;
  final Color outlineVariant;
  final Color inverseSurface;
  final Color onInverseSurface;
  final Color inversePrimary;
  final Color scrim;

  const TokenColors({
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.onTertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.surface,
    required this.onSurface,
    required this.surfaceVariant,
    required this.onSurfaceVariant,
    required this.surfaceTint,
    required this.background,
    required this.onBackground,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
    required this.outline,
    required this.outlineVariant,
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.inversePrimary,
    required this.scrim,
  });
}

const darkTokenColors = TokenColors(
  primary: Color(0xFFEBBA47),
  onPrimary: Color(0xFF0E1220),
  primaryContainer: Color(0xFF3F3212),
  onPrimaryContainer: Color(0xFFF6EBD0),
  secondary: Color(0xFF8FB0DE),
  onSecondary: Color(0xFF0E1220),
  secondaryContainer: Color(0xFF1E3355),
  onSecondaryContainer: Color(0xFFC9DCF5),
  tertiary: Color(0xFFC97B5A),
  onTertiary: Color(0xFF21120A),
  tertiaryContainer: Color(0xFF40200F),
  onTertiaryContainer: Color(0xFFF0C9B5),
  surface: Color(0xFF1F263D),
  onSurface: Color(0xFFEDEFF8),
  surfaceVariant: Color(0xFF2D385C),
  onSurfaceVariant: Color(0xFFC7CEE0),
  surfaceTint: Color(0xFFEBBA47),
  background: Color(0xFF0E1220),
  onBackground: Color(0xFFEDEFF8),
  error: Color(0xFFE5484D),
  onError: Color(0xFF1A0506),
  errorContainer: Color(0xFF470E10),
  onErrorContainer: Color(0xFFF9C8C9),
  success: Color(0xFF4FAE8A),
  onSuccess: Color(0xFF0A1F17),
  warning: Color(0xFFE2933A),
  onWarning: Color(0xFF241505),
  outline: Color(0xFF647199),
  outlineVariant: Color(0xFF3D4867),
  inverseSurface: Color(0xFFEDEFF8),
  onInverseSurface: Color(0xFF1F263D),
  inversePrimary: Color(0xFF8C6A1D),
  scrim: Color(0xFF0E1220),
);

const lightTokenColors = TokenColors(
  primary: Color(0xFF8A5A16),
  onPrimary: Color(0xFFFFF8E8),
  primaryContainer: Color(0xFFFCEFD2),
  onPrimaryContainer: Color(0xFF4A3508),
  secondary: Color(0xFF35538F),
  onSecondary: Color(0xFFF5F8FF),
  secondaryContainer: Color(0xFFDCE6F7),
  onSecondaryContainer: Color(0xFF1C355F),
  tertiary: Color(0xFF9C4A2E),
  onTertiary: Color(0xFFFFF4EE),
  tertiaryContainer: Color(0xFFF7DCD2),
  onTertiaryContainer: Color(0xFF5C2814),
  surface: Color(0xFFFFFFFF),
  onSurface: Color(0xFF12182B),
  surfaceVariant: Color(0xFFE9ECF5),
  onSurfaceVariant: Color(0xFF454F6B),
  surfaceTint: Color(0xFF8A5A16),
  background: Color(0xFFF7F8FC),
  onBackground: Color(0xFF12182B),
  error: Color(0xFFC4373A),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFBDADA),
  onErrorContainer: Color(0xFF6B1315),
  success: Color(0xFF1F7A5C),
  onSuccess: Color(0xFFF2FBF7),
  warning: Color(0xFFA85E12),
  onWarning: Color(0xFFFFF6EC),
  outline: Color(0xFF7C8598),
  outlineVariant: Color(0xFFCDD2E0),
  inverseSurface: Color(0xFF1F263D),
  onInverseSurface: Color(0xFFEDEFF8),
  inversePrimary: Color(0xFFEBBA47),
  scrim: Color(0xFF0E1220),
);

// ---------------------------------------------------------------------------
// Typography — one role per TextTheme slot, 1:1 with the JSON's role names.
// `heightMultiplier` feeds straight into TextStyle.height (unitless).
// `devanagariFallback` is the exact family name declared in pubspec.yaml's
// font list, so Hindi strings resolve without a system-default fallback.
// ---------------------------------------------------------------------------

class TokenTextRole {
  final String family;
  final FontWeight weight;
  final double size;
  final double heightMultiplier;
  final double letterSpacing;
  final String devanagariFallback;

  const TokenTextRole({
    required this.family,
    required this.weight,
    required this.size,
    required this.heightMultiplier,
    required this.letterSpacing,
    required this.devanagariFallback,
  });
}

const _fraunces = 'Fraunces';
const _manrope = 'Manrope';
const _notoSerifDevanagari = 'Noto Serif Devanagari';
const _notoSansDevanagari = 'Noto Sans Devanagari';

/// design-tokens.json `typography.fontFamilies.ui` — the app-wide default
/// (`ThemeData.fontFamily`) before any per-role override.
const tokenUiFamily = _manrope;
const tokenUiDevanagariFamily = _notoSansDevanagari;

const tokenDisplayLarge = TokenTextRole(
  family: _fraunces,
  weight: FontWeight.w600,
  size: 57,
  heightMultiplier: 1.123,
  letterSpacing: -0.25,
  devanagariFallback: _notoSerifDevanagari,
);
const tokenDisplayMedium = TokenTextRole(
  family: _fraunces,
  weight: FontWeight.w600,
  size: 45,
  heightMultiplier: 1.156,
  letterSpacing: 0,
  devanagariFallback: _notoSerifDevanagari,
);
const tokenDisplaySmall = TokenTextRole(
  family: _fraunces,
  weight: FontWeight.w600,
  size: 36,
  heightMultiplier: 1.222,
  letterSpacing: 0,
  devanagariFallback: _notoSerifDevanagari,
);
const tokenHeadlineLarge = TokenTextRole(
  family: _fraunces,
  weight: FontWeight.w600,
  size: 32,
  heightMultiplier: 1.250,
  letterSpacing: 0,
  devanagariFallback: _notoSerifDevanagari,
);
const tokenHeadlineMedium = TokenTextRole(
  family: _fraunces,
  weight: FontWeight.w500,
  size: 28,
  heightMultiplier: 1.286,
  letterSpacing: 0,
  devanagariFallback: _notoSerifDevanagari,
);
const tokenHeadlineSmall = TokenTextRole(
  family: _fraunces,
  weight: FontWeight.w500,
  size: 24,
  heightMultiplier: 1.333,
  letterSpacing: 0,
  devanagariFallback: _notoSerifDevanagari,
);
const tokenTitleLarge = TokenTextRole(
  family: _fraunces,
  weight: FontWeight.w600,
  size: 22,
  heightMultiplier: 1.273,
  letterSpacing: 0,
  devanagariFallback: _notoSerifDevanagari,
);
const tokenTitleMedium = TokenTextRole(
  family: _manrope,
  weight: FontWeight.w600,
  size: 16,
  heightMultiplier: 1.500,
  letterSpacing: 0.15,
  devanagariFallback: _notoSansDevanagari,
);
const tokenTitleSmall = TokenTextRole(
  family: _manrope,
  weight: FontWeight.w600,
  size: 14,
  heightMultiplier: 1.429,
  letterSpacing: 0.1,
  devanagariFallback: _notoSansDevanagari,
);
const tokenBodyLarge = TokenTextRole(
  family: _manrope,
  weight: FontWeight.w400,
  size: 16,
  heightMultiplier: 1.500,
  letterSpacing: 0.5,
  devanagariFallback: _notoSansDevanagari,
);
const tokenBodyMedium = TokenTextRole(
  family: _manrope,
  weight: FontWeight.w400,
  size: 14,
  heightMultiplier: 1.429,
  letterSpacing: 0.25,
  devanagariFallback: _notoSansDevanagari,
);
const tokenBodySmall = TokenTextRole(
  family: _manrope,
  weight: FontWeight.w400,
  size: 12,
  heightMultiplier: 1.333,
  letterSpacing: 0.4,
  devanagariFallback: _notoSansDevanagari,
);
const tokenLabelLarge = TokenTextRole(
  family: _manrope,
  weight: FontWeight.w600,
  size: 14,
  heightMultiplier: 1.429,
  letterSpacing: 0.1,
  devanagariFallback: _notoSansDevanagari,
);
const tokenLabelMedium = TokenTextRole(
  family: _manrope,
  weight: FontWeight.w600,
  size: 12,
  heightMultiplier: 1.333,
  letterSpacing: 0.5,
  devanagariFallback: _notoSansDevanagari,
);
const tokenLabelSmall = TokenTextRole(
  family: _manrope,
  weight: FontWeight.w600,
  size: 11,
  heightMultiplier: 1.455,
  letterSpacing: 0.5,
  devanagariFallback: _notoSansDevanagari,
);

// ---------------------------------------------------------------------------
// Spacing / radius — flat numeric scales, unitless (logical pixels).
// ---------------------------------------------------------------------------

class TokenSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const base = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xl2 = 32.0;
  static const xl3 = 40.0;
  static const xl4 = 48.0;
  static const xl5 = 64.0;
  static const xl6 = 80.0;
}

class TokenRadius {
  static const none = 0.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const full = 9999.0;
}

// ---------------------------------------------------------------------------
// Elevation — dark theme reads as tonal lift (surfaceTint opacity per level,
// applied automatically by Material 3's ElevationOverlay in dark mode); light
// theme uses conventional shadows tinted toward midnight.500 (#445BA7 ==
// rgba(68,91,167,*)) rather than neutral gray.
// ---------------------------------------------------------------------------

class TokenElevationLevel {
  final int level;
  final double dp;
  final double darkSurfaceTintOpacity;
  final List<BoxShadow> lightShadow;

  const TokenElevationLevel({
    required this.level,
    required this.dp,
    required this.darkSurfaceTintOpacity,
    required this.lightShadow,
  });
}

// Shadow tint below is midnight.500 (#445BA7) at low alpha — see design-
// tokens.json elevation.note.

const tokenElevation = <TokenElevationLevel>[
  TokenElevationLevel(
    level: 0,
    dp: 0,
    darkSurfaceTintOpacity: 0.00,
    lightShadow: [],
  ),
  TokenElevationLevel(
    level: 1,
    dp: 1,
    darkSurfaceTintOpacity: 0.05,
    lightShadow: [
      BoxShadow(
        color: Color.fromRGBO(68, 91, 167, 0.08),
        offset: Offset(0, 1),
        blurRadius: 2,
      ),
    ],
  ),
  TokenElevationLevel(
    level: 2,
    dp: 3,
    darkSurfaceTintOpacity: 0.08,
    lightShadow: [
      BoxShadow(
        color: Color.fromRGBO(68, 91, 167, 0.10),
        offset: Offset(0, 2),
        blurRadius: 6,
      ),
    ],
  ),
  TokenElevationLevel(
    level: 3,
    dp: 6,
    darkSurfaceTintOpacity: 0.11,
    lightShadow: [
      BoxShadow(
        color: Color.fromRGBO(68, 91, 167, 0.12),
        offset: Offset(0, 4),
        blurRadius: 12,
      ),
    ],
  ),
  TokenElevationLevel(
    level: 4,
    dp: 8,
    darkSurfaceTintOpacity: 0.12,
    lightShadow: [
      BoxShadow(
        color: Color.fromRGBO(68, 91, 167, 0.14),
        offset: Offset(0, 6),
        blurRadius: 16,
      ),
    ],
  ),
  TokenElevationLevel(
    level: 5,
    dp: 12,
    darkSurfaceTintOpacity: 0.14,
    lightShadow: [
      BoxShadow(
        color: Color.fromRGBO(68, 91, 167, 0.16),
        offset: Offset(0, 8),
        blurRadius: 24,
      ),
    ],
  ),
];

// ---------------------------------------------------------------------------
// Motion — "settles rather than bounces"; no bounce/elastic/spring curves.
// ---------------------------------------------------------------------------

class TokenMotionDuration {
  static const instant = Duration(milliseconds: 100);
  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 200);
  static const moderate = Duration(milliseconds: 300);
  static const slow = Duration(milliseconds: 450);
  static const slower = Duration(milliseconds: 600);
}

class TokenMotionCurve {
  static const standard = Cubic(0.2, 0, 0, 1);
  static const decelerate = Cubic(0.16, 1, 0.3, 1);
  static const accelerate = Cubic(0.4, 0, 1, 1);
  static const emphasized = Cubic(0.05, 0.7, 0.1, 1);
  static const Curve linear = Curves.linear;
}
