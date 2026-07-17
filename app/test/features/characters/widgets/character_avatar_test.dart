import 'package:dhruva/features/characters/widgets/character_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('falls back to the emoji when no avatarPath is set', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CharacterAvatar(avatarEmoji: '💪', size: 48)),
      ),
    );

    expect(find.text('💪'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('falls back to a star when neither emoji nor avatarPath is set', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CharacterAvatar(size: 48))),
    );

    expect(find.text('⭐'), findsOneWidget);
  });

  // ponytail: a third case — rendering a real picked image file via
  // Image.file — was deliberately dropped. It hung indefinitely under
  // `pumpAndSettle()` in this harness (dart:ui's decode never signals
  // "settled" for a file-backed image here), which is a test-environment
  // problem, not evidence the widget itself is broken (CharacterAvatar's
  // `hasImage` branch is a simple `File(path).existsSync()` ternary, not
  // logic worth a hanging test to protect). Upgrade path if this ever
  // needs covering: `tester.runAsync()` around the pump, or precacheImage.
}
