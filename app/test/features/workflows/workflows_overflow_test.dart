// Regression: Library > "Extract to-dos" opens the Actions screen and its
// sheet. In light theme on a 1080x2400 phone at a larger font size the privacy
// note row and the Paste / Open text file row overflowed the right edge
// ("RenderFlex overflowed by 43 pixels"). Both now wrap or shrink.

import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/features/workflows/ui/workflows_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/load_fonts.dart';

void main() {
  setUpAll(loadAppFonts);

  for (final dpr in [2.625, 3.0, 3.5]) {
    for (final scale in [1.0, 1.15, 1.3]) {
      testWidgets('Extract to-dos sheet fits: dpr $dpr, font x$scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = dpr;
        addTearDown(tester.view.reset);
        final router = GoRouter(
          initialLocation: '/a',
          routes: [
            GoRoute(
              path: '/a',
              builder: (_, _) =>
                  const WorkflowsScreen(initialWorkflowId: 'todos'),
            ),
          ],
        );
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData.fromView(
              tester.view,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: MaterialApp.router(
              theme: AppTheme.light,
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Paste'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
