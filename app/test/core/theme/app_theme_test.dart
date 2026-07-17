/// Drift-proof test (D1/D2): parses `design-tokens.json` directly from disk
/// — NOT via design_tokens.dart's hand-transcribed constants, so a mistake
/// made while transcribing can't hide from its own check — and asserts every
/// color/typography/spacing/radius/elevation/motion value the JSON declares
/// equals what `AppTheme` builds into `ThemeData`. Also proves the
/// Devanagari fallback wiring by actually rendering Hindi text with a themed
/// role (D2).
library;

import 'dart:convert';
import 'dart:io';

import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/core/theme/dhruva_theme_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// `flutter test` (via `make verify` / the Makefile) runs with cwd == the
/// `app/` package root, so the repo-root JSON is one level up.
final _tokensJson =
    jsonDecode(File('../design-tokens.json').readAsStringSync())
        as Map<String, dynamic>;

Color _hex(String hex) => Color(int.parse('FF${hex.substring(1)}', radix: 16));

Map<String, dynamic> _colors(String mode) =>
    (_tokensJson['color'] as Map<String, dynamic>)[mode]
        as Map<String, dynamic>;

FontWeight _weight(int cssWeight) => FontWeight.values[(cssWeight ~/ 100) - 1];

void main() {
  group('color — dark (design-tokens.json color.dark vs AppTheme.dark)', () {
    final json = _colors('dark');
    final scheme = AppTheme.dark.colorScheme;
    final tokens = AppTheme.dark.extension<DhruvaTokens>()!;

    test('Material-scheme roles', () {
      expect(scheme.primary, _hex(json['primary'] as String));
      expect(scheme.onPrimary, _hex(json['onPrimary'] as String));
      expect(scheme.primaryContainer, _hex(json['primaryContainer'] as String));
      expect(
        scheme.onPrimaryContainer,
        _hex(json['onPrimaryContainer'] as String),
      );
      expect(scheme.secondary, _hex(json['secondary'] as String));
      expect(scheme.onSecondary, _hex(json['onSecondary'] as String));
      expect(
        scheme.secondaryContainer,
        _hex(json['secondaryContainer'] as String),
      );
      expect(
        scheme.onSecondaryContainer,
        _hex(json['onSecondaryContainer'] as String),
      );
      expect(scheme.tertiary, _hex(json['tertiary'] as String));
      expect(scheme.onTertiary, _hex(json['onTertiary'] as String));
      expect(
        scheme.tertiaryContainer,
        _hex(json['tertiaryContainer'] as String),
      );
      expect(
        scheme.onTertiaryContainer,
        _hex(json['onTertiaryContainer'] as String),
      );
      expect(scheme.error, _hex(json['error'] as String));
      expect(scheme.onError, _hex(json['onError'] as String));
      expect(scheme.errorContainer, _hex(json['errorContainer'] as String));
      expect(scheme.onErrorContainer, _hex(json['onErrorContainer'] as String));
      expect(scheme.surface, _hex(json['surface'] as String));
      expect(scheme.onSurface, _hex(json['onSurface'] as String));
      expect(scheme.onSurfaceVariant, _hex(json['onSurfaceVariant'] as String));
      expect(scheme.surfaceTint, _hex(json['surfaceTint'] as String));
      expect(scheme.outline, _hex(json['outline'] as String));
      expect(scheme.outlineVariant, _hex(json['outlineVariant'] as String));
      expect(scheme.inverseSurface, _hex(json['inverseSurface'] as String));
      expect(scheme.onInverseSurface, _hex(json['onInverseSurface'] as String));
      expect(scheme.inversePrimary, _hex(json['inversePrimary'] as String));
      expect(scheme.scrim, _hex(json['scrim'] as String));
    });

    test('surfaceVariant -> surfaceContainerHighest (non-deprecated slot)', () {
      expect(
        scheme.surfaceContainerHighest,
        _hex(json['surfaceVariant'] as String),
      );
    });

    test(
      'background -> scaffoldBackgroundColor; onBackground == onSurface',
      () {
        expect(
          AppTheme.dark.scaffoldBackgroundColor,
          _hex(json['background'] as String),
        );
        expect(scheme.onSurface, _hex(json['onBackground'] as String));
      },
    );

    test('success/warning on the DhruvaTokens extension', () {
      expect(tokens.success, _hex(json['success'] as String));
      expect(tokens.onSuccess, _hex(json['onSuccess'] as String));
      expect(tokens.warning, _hex(json['warning'] as String));
      expect(tokens.onWarning, _hex(json['onWarning'] as String));
    });
  });

  group('color — light (design-tokens.json color.light vs AppTheme.light)', () {
    final json = _colors('light');
    final scheme = AppTheme.light.colorScheme;
    final tokens = AppTheme.light.extension<DhruvaTokens>()!;

    test('Material-scheme roles', () {
      expect(scheme.primary, _hex(json['primary'] as String));
      expect(scheme.onPrimary, _hex(json['onPrimary'] as String));
      expect(scheme.primaryContainer, _hex(json['primaryContainer'] as String));
      expect(
        scheme.onPrimaryContainer,
        _hex(json['onPrimaryContainer'] as String),
      );
      expect(scheme.secondary, _hex(json['secondary'] as String));
      expect(scheme.onSecondary, _hex(json['onSecondary'] as String));
      expect(
        scheme.secondaryContainer,
        _hex(json['secondaryContainer'] as String),
      );
      expect(
        scheme.onSecondaryContainer,
        _hex(json['onSecondaryContainer'] as String),
      );
      expect(scheme.tertiary, _hex(json['tertiary'] as String));
      expect(scheme.onTertiary, _hex(json['onTertiary'] as String));
      expect(
        scheme.tertiaryContainer,
        _hex(json['tertiaryContainer'] as String),
      );
      expect(
        scheme.onTertiaryContainer,
        _hex(json['onTertiaryContainer'] as String),
      );
      expect(scheme.error, _hex(json['error'] as String));
      expect(scheme.onError, _hex(json['onError'] as String));
      expect(scheme.errorContainer, _hex(json['errorContainer'] as String));
      expect(scheme.onErrorContainer, _hex(json['onErrorContainer'] as String));
      expect(scheme.surface, _hex(json['surface'] as String));
      expect(scheme.onSurface, _hex(json['onSurface'] as String));
      expect(scheme.onSurfaceVariant, _hex(json['onSurfaceVariant'] as String));
      expect(scheme.surfaceTint, _hex(json['surfaceTint'] as String));
      expect(scheme.outline, _hex(json['outline'] as String));
      expect(scheme.outlineVariant, _hex(json['outlineVariant'] as String));
      expect(scheme.inverseSurface, _hex(json['inverseSurface'] as String));
      expect(scheme.onInverseSurface, _hex(json['onInverseSurface'] as String));
      expect(scheme.inversePrimary, _hex(json['inversePrimary'] as String));
      expect(scheme.scrim, _hex(json['scrim'] as String));
    });

    test('surfaceVariant -> surfaceContainerHighest (non-deprecated slot)', () {
      expect(
        scheme.surfaceContainerHighest,
        _hex(json['surfaceVariant'] as String),
      );
    });

    test(
      'background -> scaffoldBackgroundColor; onBackground == onSurface',
      () {
        expect(
          AppTheme.light.scaffoldBackgroundColor,
          _hex(json['background'] as String),
        );
        expect(scheme.onSurface, _hex(json['onBackground'] as String));
      },
    );

    test('success/warning on the DhruvaTokens extension', () {
      expect(tokens.success, _hex(json['success'] as String));
      expect(tokens.onSuccess, _hex(json['onSuccess'] as String));
      expect(tokens.warning, _hex(json['warning'] as String));
      expect(tokens.onWarning, _hex(json['onWarning'] as String));
    });
  });

  group('typography (design-tokens.json typography.* vs TextTheme roles)', () {
    final json = _tokensJson['typography'] as Map<String, dynamic>;
    final textTheme = AppTheme.dark.textTheme;

    const roleNames = [
      'displayLarge',
      'displayMedium',
      'displaySmall',
      'headlineLarge',
      'headlineMedium',
      'headlineSmall',
      'titleLarge',
      'titleMedium',
      'titleSmall',
      'bodyLarge',
      'bodyMedium',
      'bodySmall',
      'labelLarge',
      'labelMedium',
      'labelSmall',
    ];

    for (final roleName in roleNames) {
      test(roleName, () {
        final roleJson = json[roleName] as Map<String, dynamic>;
        final style = _roleStyle(textTheme, roleName);
        expect(style, isNotNull, reason: '$roleName missing from TextTheme');
        expect(style!.fontFamily, roleJson['family']);
        expect(style.fontWeight, _weight(roleJson['weight'] as int));
        expect(style.fontSize, (roleJson['size'] as num).toDouble());
        expect(style.height, (roleJson['heightMultiplier'] as num).toDouble());
        expect(
          style.letterSpacing,
          (roleJson['letterSpacing'] as num).toDouble(),
        );
        expect(
          style.fontFamilyFallback,
          contains(roleJson['devanagariFallback']),
        );
      });
    }
  });

  group('spacing / radius (design-tokens.json vs DhruvaTokens)', () {
    final spacingJson = _tokensJson['spacing'] as Map<String, dynamic>;
    final radiusJson = _tokensJson['radius'] as Map<String, dynamic>;
    final tokens = AppTheme.dark.extension<DhruvaTokens>()!;

    test('spacing scale', () {
      expect(tokens.spacing.xs, (spacingJson['xs'] as num).toDouble());
      expect(tokens.spacing.sm, (spacingJson['sm'] as num).toDouble());
      expect(tokens.spacing.md, (spacingJson['md'] as num).toDouble());
      expect(tokens.spacing.base, (spacingJson['base'] as num).toDouble());
      expect(tokens.spacing.lg, (spacingJson['lg'] as num).toDouble());
      expect(tokens.spacing.xl, (spacingJson['xl'] as num).toDouble());
      expect(tokens.spacing.xl2, (spacingJson['2xl'] as num).toDouble());
      expect(tokens.spacing.xl3, (spacingJson['3xl'] as num).toDouble());
      expect(tokens.spacing.xl4, (spacingJson['4xl'] as num).toDouble());
      expect(tokens.spacing.xl5, (spacingJson['5xl'] as num).toDouble());
      expect(tokens.spacing.xl6, (spacingJson['6xl'] as num).toDouble());
    });

    test('radius scale', () {
      expect(tokens.radius.none, (radiusJson['none'] as num).toDouble());
      expect(tokens.radius.xs, (radiusJson['xs'] as num).toDouble());
      expect(tokens.radius.sm, (radiusJson['sm'] as num).toDouble());
      expect(tokens.radius.md, (radiusJson['md'] as num).toDouble());
      expect(tokens.radius.lg, (radiusJson['lg'] as num).toDouble());
      expect(tokens.radius.xl, (radiusJson['xl'] as num).toDouble());
      expect(tokens.radius.full, (radiusJson['full'] as num).toDouble());
    });
  });

  group('elevation (design-tokens.json elevation.levels vs DhruvaTokens)', () {
    final levelsJson =
        (_tokensJson['elevation'] as Map<String, dynamic>)['levels']
            as List<dynamic>;
    final elevation = AppTheme.dark.extension<DhruvaTokens>()!.elevation;

    test('6 levels, dp + dark tint opacity match', () {
      expect(elevation, hasLength(levelsJson.length));
      for (var i = 0; i < levelsJson.length; i++) {
        final levelJson = levelsJson[i] as Map<String, dynamic>;
        expect(elevation[i].level, levelJson['level']);
        expect(elevation[i].dp, (levelJson['dp'] as num).toDouble());
        expect(
          elevation[i].darkSurfaceTintOpacity,
          (levelJson['darkSurfaceTintOpacity'] as num).toDouble(),
        );
      }
    });
  });

  group('motion (design-tokens.json motion vs DhruvaTokens)', () {
    final durationJson =
        (_tokensJson['motion'] as Map<String, dynamic>)['duration']
            as Map<String, dynamic>;
    final easingJson =
        (_tokensJson['motion'] as Map<String, dynamic>)['easing']
            as Map<String, dynamic>;
    final motion = AppTheme.dark.extension<DhruvaTokens>()!.motion;

    test('durations', () {
      expect(motion.instant.inMilliseconds, durationJson['instant']);
      expect(motion.fast.inMilliseconds, durationJson['fast']);
      expect(motion.base.inMilliseconds, durationJson['base']);
      expect(motion.moderate.inMilliseconds, durationJson['moderate']);
      expect(motion.slow.inMilliseconds, durationJson['slow']);
      expect(motion.slower.inMilliseconds, durationJson['slower']);
      expect(motion.pulseMedium.inMilliseconds, durationJson['pulseMedium']);
      expect(motion.pulseSlow.inMilliseconds, durationJson['pulseSlow']);
    });

    test('easing curves (cubic-bezier control points)', () {
      _expectCubicMatches(motion.standard, easingJson['standard'] as String);
      _expectCubicMatches(
        motion.decelerate,
        easingJson['decelerate'] as String,
      );
      _expectCubicMatches(
        motion.accelerate,
        easingJson['accelerate'] as String,
      );
      _expectCubicMatches(
        motion.emphasized,
        easingJson['emphasized'] as String,
      );
      expect(easingJson['linear'], 'linear');
      expect(motion.linear, Curves.linear);
    });

    test('no bounce/elastic/spring curves used anywhere in AppTheme', () {
      // The token philosophy bans overshoot curves outright — a cheap,
      // permanent guard against a future contributor reaching for
      // Curves.elasticOut/bounceOut by habit.
      for (final c in [
        motion.standard,
        motion.decelerate,
        motion.accelerate,
        motion.emphasized,
        motion.linear,
      ]) {
        expect(c, isNot(isA<ElasticInCurve>()));
        expect(c, isNot(isA<ElasticOutCurve>()));
        expect(c, isNot(isA<ElasticInOutCurve>()));
        expect(c.runtimeType.toString(), isNot(contains('Bounce')));
      }
    });
  });

  group('Devanagari fallback — proven by rendering Hindi text', () {
    testWidgets('headlineLarge (Fraunces) renders Hindi without throwing', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => Scaffold(
              body: Text(
                'ध्रुव — आपका AI, आपका फ़ोन',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('ध्रुव — आपका AI, आपका फ़ोन'), findsOneWidget);
    });

    test('every Fraunces role falls back to Noto Serif Devanagari', () {
      final textTheme = AppTheme.dark.textTheme;
      for (final style in [
        textTheme.displayLarge,
        textTheme.displayMedium,
        textTheme.displaySmall,
        textTheme.headlineLarge,
        textTheme.headlineMedium,
        textTheme.headlineSmall,
        textTheme.titleLarge,
      ]) {
        expect(style!.fontFamily, 'Fraunces');
        expect(style.fontFamilyFallback, contains('Noto Serif Devanagari'));
      }
    });

    test('every Manrope role falls back to Noto Sans Devanagari', () {
      final textTheme = AppTheme.dark.textTheme;
      for (final style in [
        textTheme.titleMedium,
        textTheme.titleSmall,
        textTheme.bodyLarge,
        textTheme.bodyMedium,
        textTheme.bodySmall,
        textTheme.labelLarge,
        textTheme.labelMedium,
        textTheme.labelSmall,
      ]) {
        expect(style!.fontFamily, 'Manrope');
        expect(style.fontFamilyFallback, contains('Noto Sans Devanagari'));
      }
    });
  });
}

TextStyle? _roleStyle(TextTheme t, String name) => switch (name) {
  'displayLarge' => t.displayLarge,
  'displayMedium' => t.displayMedium,
  'displaySmall' => t.displaySmall,
  'headlineLarge' => t.headlineLarge,
  'headlineMedium' => t.headlineMedium,
  'headlineSmall' => t.headlineSmall,
  'titleLarge' => t.titleLarge,
  'titleMedium' => t.titleMedium,
  'titleSmall' => t.titleSmall,
  'bodyLarge' => t.bodyLarge,
  'bodyMedium' => t.bodyMedium,
  'bodySmall' => t.bodySmall,
  'labelLarge' => t.labelLarge,
  'labelMedium' => t.labelMedium,
  'labelSmall' => t.labelSmall,
  _ => throw ArgumentError('unknown role $name'),
};

/// Parses a `"cubic-bezier(a, b, c, d)"` string and asserts it matches
/// [curve]'s control points exactly.
void _expectCubicMatches(Curve curve, String cssValue) {
  final match = RegExp(
    r'cubic-bezier\(([-\d.]+),\s*([-\d.]+),\s*([-\d.]+),\s*([-\d.]+)\)',
  ).firstMatch(cssValue);
  expect(match, isNotNull, reason: 'not a cubic-bezier() string: $cssValue');
  final expected = match!
      .groups([1, 2, 3, 4])
      .map((s) => double.parse(s!))
      .toList();
  expect(curve, isA<Cubic>());
  final cubic = curve as Cubic;
  expect(cubic.a, expected[0]);
  expect(cubic.b, expected[1]);
  expect(cubic.c, expected[2]);
  expect(cubic.d, expected[3]);
}
