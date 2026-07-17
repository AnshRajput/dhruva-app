import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/chat/models/sampling_params.dart';
import 'package:dhruva/features/characters/widgets/sampling_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders one slider per SamplingParams field at its current '
      'value', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SamplingEditor(
            value: const SamplingParams(temperature: 0.5, topK: 30),
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(Slider), findsNWidgets(4));
    expect(find.text('Temperature'), findsOneWidget);
    expect(find.text('0.50'), findsOneWidget);
    expect(find.text('Top-K'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
  });

  testWidgets('dragging the temperature slider calls onChanged with an '
      'updated SamplingParams', (tester) async {
    SamplingParams? updated;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SamplingEditor(
            value: const SamplingParams(),
            onChanged: (v) => updated = v,
          ),
        ),
      ),
    );

    final temperatureSlider = find.byType(Slider).first;
    await tester.drag(temperatureSlider, const Offset(-200, 0));
    await tester.pumpAndSettle();

    expect(updated, isNotNull);
    expect(updated!.temperature, lessThan(0.8));
  });
}
