// Widget and Quick Settings tile launches showed a black frame before the app
// painted. The launch window must be the theme background (never black), and
// the Flutter embedding must keep the splash over its surface until the first
// frame. These tests read the platform files.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const res = 'android/app/src/main/res';
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();

  String splashColor(String valuesDir) =>
      RegExp(r'<color name="splash_background">(#[0-9A-Fa-f]{6})</color>')
          .firstMatch(File('$res/$valuesDir/colors.xml').readAsStringSync())!
          .group(1)!;

  test('both launch activities keep the splash over the Flutter surface', () {
    final tags = RegExp(
      'io.flutter.embedding.android.SplashScreenDrawable',
    ).allMatches(manifest);
    // MainActivity (icon, widget, tile) and ProcessTextActivity.
    expect(tags.length, 2);
    expect(
      manifest,
      contains('android:resource="@drawable/launch_background"'),
    );
  });

  test('launch and normal themes paint the splash colour, not black', () {
    for (final dir in ['values', 'values-night', 'values-v31']) {
      final styles = File('$res/$dir/styles.xml').readAsStringSync();
      expect(styles, contains('@color/splash_background'), reason: dir);
      expect(styles, isNot(contains('@android:color/black')), reason: dir);
    }
  });

  test('splash colours are the design tokens for light and dark', () {
    final tokens =
        jsonDecode(File('../design-tokens.json').readAsStringSync())
            as Map<String, dynamic>;
    final color = tokens['color'] as Map<String, dynamic>;
    String bg(String mode) =>
        ((color[mode] as Map<String, dynamic>)['background'] as String)
            .toUpperCase();
    expect(splashColor('values').toUpperCase(), bg('light'));
    expect(splashColor('values-night').toUpperCase(), bg('dark'));
  });
}
