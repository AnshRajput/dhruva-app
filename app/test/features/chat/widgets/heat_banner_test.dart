import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/features/chat/widgets/heat_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.dark,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('shows the warning and a working "Use a lighter model" action', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(_host(HeatBanner(onUseLighterModel: () => taps++)));

    expect(find.text(HeatBanner.message), findsOneWidget);
    await tester.tap(find.text('Use a lighter model'));
    expect(taps, 1);
    expect(
      tester.getSize(find.byType(TextButton)).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('hides the action when there is no lighter model', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const HeatBanner()));
    expect(find.text(HeatBanner.message), findsOneWidget);
    expect(find.text('Use a lighter model'), findsNothing);
  });

  testWidgets('stopped-early note explains what happened', (tester) async {
    await tester.pumpWidget(_host(const HeatStoppedNote()));
    expect(find.text(HeatStoppedNote.message), findsOneWidget);
  });
}
