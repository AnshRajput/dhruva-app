/// Builds `ThemeData` for both modes straight from `design-tokens.json`
/// (mirrored in design_tokens.dart — see that file's header for the
/// drift-proofing contract). Dark is the hero/default per ADR-003.
///
/// Mapping notes for anyone diffing this against the JSON:
/// - JSON `background`/`onBackground` have no live slot in Flutter's
///   `ColorScheme` (deprecated in favor of `surface`/`onSurface` since
///   3.18). `onBackground` equals `onSurface` byte-for-byte in the JSON, so
///   nothing is lost; `background` becomes `scaffoldBackgroundColor`
///   explicitly, keeping the JSON's screen-backdrop/component-surface
///   distinction intact without touching a deprecated constructor param.
/// - JSON `surfaceVariant` maps to `ColorScheme.surfaceContainerHighest`,
///   the non-deprecated M3 replacement slot for that role (the old
///   `surfaceVariant` param is deprecated in favor of it).
/// - `success`/`warning` have no `ColorScheme` slot at all — they live on
///   the `DhruvaTokens` theme extension instead.
library;

import 'package:flutter/material.dart';

import 'design_tokens.dart';
import 'dhruva_theme_extension.dart';

abstract final class AppTheme {
  static ThemeData get dark => _build(Brightness.dark, darkTokenColors);
  static ThemeData get light => _build(Brightness.light, lightTokenColors);

  static ThemeData _build(Brightness brightness, TokenColors c) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      primaryContainer: c.primaryContainer,
      onPrimaryContainer: c.onPrimaryContainer,
      secondary: c.secondary,
      onSecondary: c.onSecondary,
      secondaryContainer: c.secondaryContainer,
      onSecondaryContainer: c.onSecondaryContainer,
      tertiary: c.tertiary,
      onTertiary: c.onTertiary,
      tertiaryContainer: c.tertiaryContainer,
      onTertiaryContainer: c.onTertiaryContainer,
      error: c.error,
      onError: c.onError,
      errorContainer: c.errorContainer,
      onErrorContainer: c.onErrorContainer,
      surface: c.surface,
      onSurface: c.onSurface,
      surfaceContainerHighest: c.surfaceVariant,
      onSurfaceVariant: c.onSurfaceVariant,
      surfaceTint: c.surfaceTint,
      outline: c.outline,
      outlineVariant: c.outlineVariant,
      inverseSurface: c.inverseSurface,
      onInverseSurface: c.onInverseSurface,
      inversePrimary: c.inversePrimary,
      scrim: c.scrim,
    );

    final textTheme = _buildTextTheme(c.onSurface);
    final radius = const TokenRadiusScale();

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: c.background,
      fontFamily: tokenUiFamily,
      fontFamilyFallback: const [tokenUiDevanagariFamily],
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.onBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: tokenElevation[1].dp,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: tokenElevation[1].dp,
        color: c.surface,
        surfaceTintColor: c.surfaceTint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius.lg),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius.full),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: c.surfaceTint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius.xl),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: c.surfaceTint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radius.xl)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: c.onInverseSurface,
        ),
        actionTextColor: c.inversePrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius.sm),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius.sm),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius.full),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: c.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius.full),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius.full),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.outlineVariant, thickness: 1),
      extensions: [DhruvaTokens.fromColors(c)],
    );
  }

  static TextTheme _buildTextTheme(Color color) => TextTheme(
    displayLarge: _style(tokenDisplayLarge, color),
    displayMedium: _style(tokenDisplayMedium, color),
    displaySmall: _style(tokenDisplaySmall, color),
    headlineLarge: _style(tokenHeadlineLarge, color),
    headlineMedium: _style(tokenHeadlineMedium, color),
    headlineSmall: _style(tokenHeadlineSmall, color),
    titleLarge: _style(tokenTitleLarge, color),
    titleMedium: _style(tokenTitleMedium, color),
    titleSmall: _style(tokenTitleSmall, color),
    bodyLarge: _style(tokenBodyLarge, color),
    bodyMedium: _style(tokenBodyMedium, color),
    bodySmall: _style(tokenBodySmall, color),
    labelLarge: _style(tokenLabelLarge, color),
    labelMedium: _style(tokenLabelMedium, color),
    labelSmall: _style(tokenLabelSmall, color),
  );

  static TextStyle _style(TokenTextRole role, Color color) => TextStyle(
    fontFamily: role.family,
    fontFamilyFallback: [role.devanagariFallback],
    fontWeight: role.weight,
    fontSize: role.size,
    height: role.heightMultiplier,
    letterSpacing: role.letterSpacing,
    color: color,
  );
}
