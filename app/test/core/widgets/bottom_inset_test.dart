// The gesture-bar inset: sheets and explicit-padding lists clear it, so the
// last row never ends under the system gesture pill.

import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/core/widgets/bottom_inset.dart';
import 'package:dhruva/core/widgets/dhruva_sheet.dart';
import 'package:dhruva/features/workflows/ui/workflows_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _bar = 34.0;
const _screen = Size(400, 800);

/// A phone with a [_bar] dp gesture bar.
Widget _phone(Widget home) => MaterialApp(
  theme: AppTheme.dark,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      size: _screen,
      padding: const EdgeInsets.only(bottom: _bar),
      viewPadding: const EdgeInsets.only(bottom: _bar),
    ),
    child: child!,
  ),
  home: home,
);

void main() {
  testWidgets('a sheet built with showDhruvaSheet clears the gesture bar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(_screen);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _phone(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDhruvaSheet<void>(
              context: context,
              builder: (_) => const SizedBox(
                key: ValueKey('sheet-content'),
                height: 60,
                width: double.infinity,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final bottom = tester.getBottomLeft(
      find.byKey(const ValueKey('sheet-content')),
    );
    expect(bottom.dy, lessThanOrEqualTo(_screen.height - _bar));
  });

  testWidgets(
    'the Actions list scrolls its last row clear of the gesture bar',
    (tester) async {
      await tester.binding.setSurfaceSize(_screen);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_phone(const WorkflowsScreen()));
      await tester.pumpAndSettle();
      final list = find.byType(ListView).first;
      await tester.drag(list, const Offset(0, -5000));
      await tester.pumpAndSettle();
      final padding = tester.widget<ListView>(list).padding! as EdgeInsets;
      expect(padding.bottom, greaterThanOrEqualTo(_bar));
    },
  );

  testWidgets('withBottomInset adds the system inset to the padding', (
    tester,
  ) async {
    late EdgeInsets padded;
    await tester.pumpWidget(
      _phone(
        Builder(
          builder: (context) {
            padded = const EdgeInsets.all(16).withBottomInset(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(padded, const EdgeInsets.fromLTRB(16, 16, 16, 16 + _bar));
  });
}
