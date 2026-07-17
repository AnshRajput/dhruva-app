import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/features/chat/widgets/composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  required bool isGenerating,
  required ValueChanged<String> onSend,
  VoidCallback? onCancel,
  VoidCallback? onOpenSettings,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: Composer(
          isGenerating: isGenerating,
          onSend: onSend,
          onCancel: onCancel ?? () {},
          onOpenSettings: onOpenSettings ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'send button is disabled with empty text, enabled once text is typed',
    (tester) async {
      await _pump(tester, isGenerating: false, onSend: (_) {});

      final sendButton = tester.widget<IconButton>(
        find.byType(IconButton).last,
      );
      expect(sendButton.onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'hi');
      await tester.pump();

      final enabledButton = tester.widget<IconButton>(
        find.byType(IconButton).last,
      );
      expect(enabledButton.onPressed, isNotNull);
    },
  );

  testWidgets('tapping send fires onSend and clears the field', (tester) async {
    String? sent;
    await _pump(tester, isGenerating: false, onSend: (text) => sent = text);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    await tester.tap(find.byType(IconButton).last);
    await tester.pump();

    expect(sent, 'hello');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('generating shows a stop button that fires onCancel', (
    tester,
  ) async {
    var cancelled = false;
    await _pump(
      tester,
      isGenerating: true,
      onSend: (_) {},
      onCancel: () => cancelled = true,
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.stop_rounded));
    expect(cancelled, isTrue);
  });

  testWidgets('sliders icon opens settings', (tester) async {
    var opened = false;
    await _pump(
      tester,
      isGenerating: false,
      onSend: (_) {},
      onOpenSettings: () => opened = true,
    );

    await tester.tap(find.byIcon(Icons.tune));
    expect(opened, isTrue);
  });
}
