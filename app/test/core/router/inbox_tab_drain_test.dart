// The Inbox is a StatefulShellRoute indexedStack branch: its initState runs
// once. A notification posted while another tab is showing must still be in the
// list the moment the Inbox tab is tapped again.

import 'dart:convert';
import 'dart:io';

import 'package:dhruva/core/di/connector_providers.dart';
import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/data/connectors/notification_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/app_harness.dart';
import '../../support/fake_connector_sources.dart';

void main() {
  testWidgets('tapping the Inbox tab again drains notifications posted since', (
    tester,
  ) async {
    late final ConnectorTestKit kit;

    void queue(String title) =>
        File(
          p.join(kit.queueDir.path, NotificationQueue.liveName),
        ).writeAsStringSync(
          '${jsonEncode({'v': 1, 'pkg': 'com.chat.app', 'app': 'Chat', 'title': title, 'text': 'hi', 't': DateTime.now().millisecondsSinceEpoch})}\n',
          mode: FileMode.append,
        );

    Future<void> real() async {
      for (var i = 0; i < 15; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await pumpDhruvaApp(
      tester,
      location: '/inbox',
      overrides: [
        connectorHubProvider.overrideWith((ref) async {
          kit = ConnectorTestKit.create(ref.read(appDatabaseProvider));
          addTearDown(kit.dispose);
          kit.notifications.granted = true;
          await kit.hub.notifications.connect();
          return kit.hub;
        }),
      ],
    );
    await real();
    await tester.tap(find.text('Today').last);
    await tester.pumpAndSettle();

    queue('Neha');
    await tester.tap(find.text('Inbox').last);
    await real();
    await tester.pumpAndSettle();
    expect(find.text('Neha'), findsOneWidget);
  });
}
