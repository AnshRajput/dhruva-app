// The `/ask/new` contract (core/router/ask_route.dart): Today's "Prep me for
// <event>" builds the location with `askNewLocation`; the route turns it back
// into a prefilled composer with sources pinned.

import 'package:dhruva/core/di/ask_providers.dart';
import 'package:dhruva/core/router/app_router.dart';
import 'package:dhruva/core/router/ask_route.dart';
import 'package:dhruva/data/connectors/ask_sources.dart';
import 'package:dhruva/data/connectors/connector.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/engine_bindings/engine_service.dart';
import 'package:dhruva/engine_bindings/fake_engine_service.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_harness.dart';
import '../../support/device_health_fakes.dart';

void main() {
  group('askNewLocation / parseAskNewQuery', () {
    test('a bare location has no query', () {
      expect(askNewLocation(), '/ask/new');
    });

    test('q and sources round-trip, sources in chip order', () {
      final loc = askNewLocation(
        q: 'Prep me for Budget review & Q4 plan',
        sources: {AskSource.files, AskSource.calendar, AskSource.contacts},
      );
      final uri = Uri.parse(loc);
      expect(uri.path, '/ask/new');
      expect(uri.queryParameters['sources'], 'calendar,contacts,files');
      final parsed = parseAskNewQuery(uri.queryParameters);
      expect(parsed.draft, 'Prep me for Budget review & Q4 plan');
      expect(parsed.sources, {
        AskSource.calendar,
        AskSource.contacts,
        AskSource.files,
      });
    });

    test('blank q and unknown sources are ignored', () {
      final parsed = parseAskNewQuery({'q': '   ', 'sources': 'bogus,,files'});
      expect(parsed.draft, isNull);
      expect(parsed.sources, {AskSource.files});
      expect(askNewLocation(q: ' '), '/ask/new');
    });

    test('an oversized prefill is cut', () {
      final parsed = parseAskNewQuery({'q': 'x' * (maxAskPrefillChars + 50)});
      expect(parsed.draft!.length, maxAskPrefillChars);
    });

    test('/ask/new is a full-screen route, not a shell branch', () {
      expect(isShellLocation('/ask/new?q=hi'), isFalse);
      expect(isShellLocation('/ask'), isTrue);
    });
  });

  testWidgets('the route arrives prefilled with the sources pinned', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final engine = FakeEngineService();
    final db = await pumpDhruvaApp(
      tester,
      overrides: [
        engineServiceProvider.overrideWithValue(engine),
        askConnectorsProvider.overrideWithValue(const {
          ConnectorIds.calendar: true,
          ConnectorIds.contacts: true,
          ConnectorIds.folder: true,
        }),
        ...deviceHealthTestOverrides(),
      ],
    );
    await db
        .into(db.installedModels)
        .insert(
          InstalledModelsCompanion.insert(
            repoId: 'bartowski/Llama-3.2-1B-Instruct-GGUF',
            fileName: 'model.gguf',
            sizeBytes: 100,
            localPath: '/tmp/dhruva-ask-route-test.gguf',
            downloadedAt: DateTime.utc(2026, 7, 17),
          ),
        );

    appRouter.push(
      askNewLocation(
        q: 'Prep me for Budget review',
        sources: {AskSource.calendar, AskSource.contacts, AskSource.files},
      ),
    );
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'Prep me for Budget review');
    expect(find.bySemanticsLabel('Calendar, searched'), findsOneWidget);
    expect(find.bySemanticsLabel('Contacts, searched'), findsOneWidget);
    expect(find.bySemanticsLabel('Files, searched'), findsOneWidget);
    // Prefilled, never auto-sent.
    expect(engine.generateCount, 0);
    handle.dispose();
  });
}
