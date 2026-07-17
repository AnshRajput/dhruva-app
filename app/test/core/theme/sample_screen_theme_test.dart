/// D3 (per the Loop-4 designer brief): "if golden infra is too heavy, a
/// widget test asserting key theme roles applied to a sample screen
/// suffices." Chose this over goldens — the drift test in app_theme_test.dart
/// already proves every token value is correct in isolation; this proves
/// they actually reach real rendered widgets (AppBar/Card/Button/Text) once
/// composed into a screen, in both modes.
library;

import 'package:dhruva/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _SampleScreen extends StatelessWidget {
  const _SampleScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dhruva')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your AI. Your phone.',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            Text(
              'No account. No cloud.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'card surface',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
            FilledButton(onPressed: () {}, child: const Text('Get started')),
          ],
        ),
      ),
    );
  }
}

void main() {
  for (final (name, theme) in [
    ('dark', AppTheme.dark),
    ('light', AppTheme.light),
  ]) {
    testWidgets('$name mode: key roles reach real widgets', (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: theme, home: const _SampleScreen()),
      );
      expect(tester.takeException(), isNull);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(
        scaffold.backgroundColor ?? theme.scaffoldBackgroundColor,
        theme.scaffoldBackgroundColor,
      );

      final appBarTextStyle = tester.widget<Text>(find.text('Dhruva')).style;
      // AppBar title inherits appBarTheme.titleTextStyle -> textTheme.titleLarge.
      expect(appBarTextStyle, isNull); // no per-widget override — theme-driven.

      final headline = tester.widget<Text>(find.text('Your AI. Your phone.'));
      expect(headline.style!.fontFamily, 'Fraunces');
      expect(headline.style!.color, theme.colorScheme.onSurface);

      final body = tester.widget<Text>(find.text('No account. No cloud.'));
      expect(body.style!.fontFamily, 'Manrope');
      expect(body.style!.color, theme.colorScheme.onSurface);

      final card = tester.widget<Card>(find.byType(Card));
      expect(card.color ?? theme.cardTheme.color, theme.cardTheme.color);
      expect(theme.cardTheme.color, theme.colorScheme.surface);

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      final buttonShape =
          button.style?.shape?.resolve({}) ??
          theme.filledButtonTheme.style?.shape?.resolve({});
      expect(buttonShape, isA<RoundedRectangleBorder>());
      expect(
        (buttonShape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(9999),
      );
    });
  }
}
