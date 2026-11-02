// Wave 3B: the Connectors screen. Card states and transitions, the disconnect
// flow (wipes data, deep-links to the OS page on request), the privacy ledger,
// the folder index controls, notification apps, and refresh on app resume.

import 'dart:async';

import 'package:dhruva/core/di/connector_providers.dart';
import 'package:dhruva/data/connectors/connector.dart';
import 'package:dhruva/data/connectors/connector_hub.dart';
import 'package:dhruva/data/connectors/connector_sources.dart';
import 'package:dhruva/features/settings/ui/connectors_screen.dart';
import 'package:dhruva/features/settings/ui/ledger_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/connector_ui_harness.dart';
import '../../../support/fake_connector_sources.dart';
import '../../../support/load_fonts.dart';

/// The screen with the app-root resume hook the real app has.
class _Host extends ConsumerWidget {
  const _Host();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(connectorResumeProvider);
    return const ConnectorsScreen();
  }
}

Finder _key(String k) => find.byKey(ValueKey(k));

void main() {
  group('card states', () {
    testWidgets('lists the four connectors, not connected, with what each '
        'can read; Gmail is not offered', (tester) async {
      await pumpConnectorScreen(tester, const _Host());
      for (final id in ['calendar', 'contacts', 'folder', 'notifications']) {
        expect(_key('connector-$id'), findsOneWidget, reason: id);
        expect(_key('connector-$id-action'), findsOneWidget, reason: id);
      }
      expect(find.text('Not connected'), findsNWidgets(4));
      expect(find.text('Choose what Dhruva can read.'), findsOneWidget);
      expect(find.textContaining('who is invited'), findsOneWidget);
      expect(
        find.textContaining('verification codes are hidden'),
        findsOneWidget,
      );
      expect(find.textContaining('Gmail'), findsNothing);
      expect(find.text('Android'), findsOneWidget);
    });

    testWidgets('cards run Calendar, Contacts, Notes folder, Notifications, '
        'top to bottom', (tester) async {
      await pumpConnectorScreen(tester, const _Host());
      final ys = [
        for (final id in ['calendar', 'contacts', 'folder', 'notifications'])
          tester.getTopLeft(_key('connector-$id')).dy,
      ];
      expect(ys, orderedEquals([...ys]..sort()));
      expect(ys.toSet(), hasLength(4));
    });

    testWidgets('360dp with the real font: names stay whole, the action sits '
        'under the text, nothing overflows', (tester) async {
      await loadAppFonts();
      await pumpConnectorScreen(
        tester,
        const _Host(),
        surface: const Size(360, 800),
      );
      expect(tester.takeException(), isNull);
      for (final id in ['calendar', 'contacts', 'folder', 'notifications']) {
        final row = tester.getRect(_key('connector-$id'));
        final button = tester.getRect(_key('connector-$id-action'));
        expect(button.right, lessThanOrEqualTo(row.right), reason: id);
      }
      // Names are one unbroken line (not wrapped mid-word).
      expect(tester.getSize(find.text('Notifications')).height, lessThan(30));
      expect(tester.getSize(find.text('Notes folder')).height, lessThan(30));
      // The action is below the name, not squeezing it.
      expect(
        tester.getTopLeft(_key('connector-notifications-action')).dy,
        greaterThan(tester.getBottomLeft(find.text('Notifications')).dy),
      );
    });

    testWidgets('notifications are not listed where the platform has no '
        'listener (iOS)', (tester) async {
      await pumpConnectorScreen(
        tester,
        const _Host(),
        notificationsSupported: false,
      );
      expect(_key('connector-notifications'), findsNothing);
      expect(_key('connector-calendar'), findsOneWidget);
    });

    testWidgets('loading shows skeleton rows, not a spinner or a blank page', (
      tester,
    ) async {
      final never = Completer<ConnectorHub>();
      await pumpConnectorScreen(tester, const _Host(), hubFuture: never.future);
      expect(_key('connectors-skeleton-0'), findsOneWidget);
      expect(find.text('Not connected'), findsNothing);
    });

    testWidgets('connect: not connected -> connected, with the ledger entry', (
      tester,
    ) async {
      final ui = await pumpConnectorScreen(tester, const _Host());
      ui.kit.calendar.items = [
        calEvent('e1', start: DateTime.now().add(const Duration(hours: 1))),
        calEvent('e2', start: DateTime.now().add(const Duration(hours: 2))),
      ];
      await tester.tap(_key('connector-calendar-action'));
      await tester.pumpAndSettle();
      expect(ui.kit.calendar.requests, 1);
      expect(find.textContaining('Connected'), findsWidgets);
      // The row now opens its sheet instead of offering Connect.
      expect(_key('connector-calendar-action'), findsNothing);
      // Ledger: connected + the first read.
      expect(find.text('Read 2 events'), findsOneWidget);
      expect(find.text('Connected'), findsWidgets);
      // The background job is scheduled once something is connected.
      expect(ui.scheduler.scheduled, 1);
    });

    testWidgets('first and second system Deny both answer inline: retry copy, '
        'then blocked copy with Open settings; allowing it in settings and '
        'returning connects by itself', (tester) async {
      final ui = await pumpConnectorScreen(tester, const _Host());

      // 1st Deny: the system will ask again.
      ui.kit.calendar.afterRequest = DevicePermission.notDetermined;
      await tester.tap(_key('connector-calendar-action'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(_key('connector-calendar-feedback')).data,
        contains('Tap Connect to try again'),
      );
      expect(find.text('Not connected'), findsNWidgets(4));
      expect(find.text('Open settings'), findsNothing);

      // 2nd Deny: Android will not ask any more.
      ui.kit.calendar.afterRequest = DevicePermission.denied;
      await tester.tap(_key('connector-calendar-action'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(_key('connector-calendar-feedback')).data,
        contains('blocked'),
      );
      expect(find.text('Open settings'), findsOneWidget);
      // Still an ordinary row, not a "needs attention" card.
      expect(find.text('Needs attention'), findsNothing);

      await tester.tap(_key('connector-calendar-action'));
      await tester.pumpAndSettle();
      expect(ui.kit.calendar.settingsOpened, 1);

      // Allowed in system settings; coming back connects it.
      ui.kit.calendar.items = [
        calEvent('e1', start: DateTime.now().add(const Duration(hours: 1))),
      ];
      ui.kit.calendar.perm = DevicePermission.granted;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(_key('connector-calendar-feedback'), findsNothing);
      expect(find.text('Open settings'), findsNothing);
      expect(find.textContaining('Connected'), findsWidgets);
      expect(await ui.kit.hub.store.countItems('calendar'), 1);
    });

    testWidgets('a grant switched off later is a fix card with the revoked '
        'copy, not the first-time copy', (tester) async {
      final ui = await pumpConnectorScreen(tester, const _Host());
      await tester.tap(_key('connector-calendar-action'));
      await tester.pumpAndSettle();
      ui.kit.calendar.perm = DevicePermission.denied;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Needs attention'), findsNothing);
      expect(find.text('Access is off'), findsOneWidget);
      expect(find.textContaining('bring your events back'), findsWidgets);
      expect(find.text('Open settings'), findsOneWidget);
      await tester.tap(_key('connector-calendar-action'));
      await tester.pumpAndSettle();
      expect(ui.kit.calendar.settingsOpened, 1);
    });

    testWidgets('needs attention: notifications access off -> reason + fix; '
        'granting it in system settings and returning fixes the card and '
        'schedules the background job (resume refresh)', (tester) async {
      final ui = await pumpConnectorScreen(tester, const _Host());
      await tester.tap(_key('connector-notifications-action'));
      await tester.pumpAndSettle();
      // The OS page was opened, and the card says what is wrong.
      expect(ui.kit.notifications.settingsOpened, 1);
      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.textContaining('One more step'), findsWidgets);
      expect(find.text('Turn on access'), findsOneWidget);
      expect(ui.scheduler.scheduled, 0);

      // The user flips the switch in system settings and comes back.
      ui.kit.notifications.granted = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Needs attention'), findsNothing);
      expect(find.textContaining('Connected'), findsWidgets);
      expect(ui.scheduler.scheduled, 1, reason: 'job follows the transition');
    });

    testWidgets('revoking access in system settings is noticed on resume', (
      tester,
    ) async {
      final ui = await pumpConnectorScreen(tester, const _Host());
      ui.kit.notifications.granted = true;
      await tester.tap(_key('connector-notifications-action'));
      await tester.pumpAndSettle();
      expect(find.text('Needs attention'), findsNothing);

      ui.kit.notifications.granted = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Needs attention'), findsOneWidget);
    });
  });

  group('disconnect', () {
    Future<ConnectorUi> connectedCalendar(WidgetTester tester) async {
      final ui = await pumpConnectorScreen(tester, const _Host());
      ui.kit.calendar.items = [
        calEvent('e1', start: DateTime.now().add(const Duration(hours: 1))),
      ];
      await tester.tap(_key('connector-calendar-action'));
      await tester.pumpAndSettle();
      expect(await ui.kit.hub.store.countItems('calendar'), 1);
      await tester.tap(_key('connector-calendar'));
      await tester.pumpAndSettle();
      return ui;
    }

    testWidgets('confirms with the consequences in plain words; cancel '
        'changes nothing', (tester) async {
      final ui = await connectedCalendar(tester);
      await tester.tap(_key('connector-disconnect'));
      await tester.pumpAndSettle();
      expect(find.text('Disconnect Calendar?'), findsOneWidget);
      expect(
        find.text(
          'Removes the copy of your events on this phone. Your calendar '
          'itself is untouched.',
        ),
        findsWidgets,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await ui.kit.hub.store.countItems('calendar'), 1);
      expect(ui.kit.calendar.settingsOpened, 0);
    });

    testWidgets('wipes the local copy and does NOT open system settings '
        'unless asked', (tester) async {
      final ui = await connectedCalendar(tester);
      await tester.tap(_key('connector-disconnect'));
      await tester.pumpAndSettle();
      await tester.tap(_key('disconnect-confirm'));
      await tester.pumpAndSettle();
      expect(await ui.kit.hub.store.countItems('calendar'), 0);
      expect(await ui.kit.hub.store.account('calendar'), isNull);
      expect(ui.kit.calendar.settingsOpened, 0);
      expect(find.text('Disconnected and deleted the copy'), findsOneWidget);
      // Nothing left connected: the background job is cancelled.
      expect(ui.scheduler.cancelled, greaterThan(0));
      expect(_key('connector-calendar-action'), findsOneWidget);
    });

    testWidgets('"Disconnect and open Settings" wipes the copy and '
        'calls the OS deep link', (tester) async {
      final ui = await connectedCalendar(tester);
      await tester.tap(_key('connector-disconnect'));
      await tester.pumpAndSettle();
      await tester.tap(_key('disconnect-and-settings'));
      await tester.pumpAndSettle();
      expect(await ui.kit.hub.store.countItems('calendar'), 0);
      expect(ui.kit.calendar.settingsOpened, 1);
    });

    testWidgets('the folder has no OS permission page to offer, and '
        'releases its grant', (tester) async {
      final ui = await pumpConnectorScreen(tester, const _Host());
      ui.kit.folder.nextPick = const FolderGrant(id: 'tree:1', name: 'Notes');
      await tester.tap(_key('connector-folder-action'));
      await tester.pumpAndSettle();
      await tester.tap(_key('connector-folder'));
      await tester.pumpAndSettle();
      await tester.tap(_key('connector-disconnect'));
      await tester.pumpAndSettle();
      expect(_key('disconnect-and-settings'), findsNothing);
      await tester.tap(_key('disconnect-confirm'));
      await tester.pumpAndSettle();
      expect(ui.kit.folder.released, contains('tree:1'));
    });
  });

  group('folder index', () {
    Future<ConnectorUi> openFolderSheet(
      WidgetTester tester, {
      Map<String, String> files = const {},
      int? total,
    }) async {
      final ui = await pumpConnectorScreen(tester, const _Host());
      await seedFolder(ui, files, total: total);
      await ui.kit.hub.folder.refreshStatus();
      await tester.pumpAndSettle();
      await tester.tap(_key('connector-folder'));
      await tester.pumpAndSettle();
      return ui;
    }

    testWidgets('status in plain words: N of M ready, what happens next', (
      tester,
    ) async {
      await openFolderSheet(
        tester,
        files: {'a.md': 'alpha', 'b.md': 'beta'},
        total: 3,
      );
      expect(
        find.textContaining('2 of 3 files ready to search'),
        findsOneWidget,
      );
      expect(find.textContaining('Finishes while charging'), findsOneWidget);
      expect(find.text('Documents/Notes'), findsOneWidget);
    });

    testWidgets('"Index now" is explicit and works on battery', (tester) async {
      final ui = await openFolderSheet(tester);
      ui.kit.charging.value = false;
      await tester.tap(_key('folder-index-now'));
      await tester.pumpAndSettle();
      expect(ui.kit.folder.listCalls, 1, reason: 'it listed the folder');
      expect(find.textContaining('No files found'), findsOneWidget);
    });

    testWidgets('while indexing: progress, "Indexing now" and a Cancel '
        'button that calls the connector', (tester) async {
      final ui = await openFolderSheet(
        tester,
        files: {'a.md': 'alpha'},
        total: 3,
      );
      ui.kit.hub.folder.emit(const ConnectorStatus(ConnectorState.syncing));
      await tester.pumpAndSettle();
      expect(_key('folder-cancel-index'), findsOneWidget);
      expect(_key('folder-index-now'), findsNothing);
      expect(find.textContaining('Indexing now'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      // Change folder is held back while a run is in progress.
      final change = tester.widget<OutlinedButton>(_key('folder-change'));
      expect(change.onPressed, isNull);
      await tester.tap(_key('folder-cancel-index'));
      await tester.pump();
    });

    testWidgets('Change folder opens the system picker again', (tester) async {
      final ui = await openFolderSheet(tester);
      ui.kit.folder.nextPick = const FolderGrant(id: 'tree:2', name: 'Work');
      await tester.tap(_key('folder-change'));
      await tester.pumpAndSettle();
      expect(ui.kit.folder.released, contains('tree:1'));
      final account = await ui.kit.hub.store.account('folder');
      expect(account!.config['grantId'], 'tree:2');
    });

    testWidgets('folder gone: the card says so and offers Choose again', (
      tester,
    ) async {
      final ui = await openFolderSheet(tester, files: {'a.md': 'alpha'});
      Navigator.of(tester.element(find.byType(ConnectorsScreen))).pop();
      await tester.pumpAndSettle();
      ui.kit.folder.reachable = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.textContaining('no longer available'), findsOneWidget);
      expect(find.text('Choose again'), findsOneWidget);
    });
  });

  group('notifications', () {
    testWidgets('explains the special access; the apps picker lists apps '
        'that posted and saves the ones to skip', (tester) async {
      final ui = await pumpConnectorScreen(tester, const _Host());
      ui.kit.notifications.granted = true;
      await tester.tap(_key('connector-notifications-action'));
      await tester.pumpAndSettle();
      await ui.kit.hub.store.upsertItems('notifications', [
        ItemDraft(
          externalId: 'n1',
          kind: ItemKind.notification,
          title: 'Hi',
          body: 'hello',
          sentAt: DateTime.now(),
          flags: const {'pkg': 'com.slack', 'app': 'Slack'},
        ),
      ]);
      await tester.tap(_key('connector-notifications'));
      await tester.pumpAndSettle();
      expect(find.textContaining('special switch'), findsOneWidget);
      await tester.tap(_key('notification-apps'));
      await tester.pumpAndSettle();
      expect(_key('skip-com.slack'), findsOneWidget);
      await tester.tap(_key('skip-com.slack'));
      await tester.pumpAndSettle();
      expect(ui.kit.notifications.excluded, contains('com.slack'));
    });

    testWidgets('no apps yet: says when they will show up', (tester) async {
      final ui = await pumpConnectorScreen(tester, const _Host());
      ui.kit.notifications.granted = true;
      await tester.tap(_key('connector-notifications-action'));
      await tester.pumpAndSettle();
      await tester.tap(_key('connector-notifications'));
      await tester.pumpAndSettle();
      await tester.tap(_key('notification-apps'));
      await tester.pumpAndSettle();
      expect(_key('excluded-apps-empty'), findsOneWidget);
    });
  });

  group('privacy ledger', () {
    testWidgets('header fact, empty note, entries newest first, See all', (
      tester,
    ) async {
      final ui = await pumpConnectorScreen(tester, const _Host());
      expect(
        find.text("0 bytes sent to any Dhruva server. There isn't one."),
        findsOneWidget,
      );
      expect(find.textContaining('Nothing has been read yet'), findsOneWidget);

      final store = ui.kit.hub.store;
      await store.addLedger('calendar', LedgerAction.read, count: 4);
      await store.addLedger('folder', LedgerAction.read, count: 1);
      await tester.pumpAndSettle();
      expect(find.text('Read 4 events'), findsOneWidget);
      expect(find.text('Read 1 file'), findsOneWidget);
      expect(find.text('Calendar'), findsWidgets);
      // Newest first.
      expect(
        tester.getTopLeft(find.text('Read 1 file')).dy,
        lessThan(tester.getTopLeft(find.text('Read 4 events')).dy),
      );
      expect(_key('ledger-see-all'), findsOneWidget);
    });

    testWidgets('the full ledger lists everything and clearing empties it', (
      tester,
    ) async {
      final ui = await pumpConnectorScreen(tester, const LedgerScreen());
      final store = ui.kit.hub.store;
      for (var i = 1; i <= 8; i++) {
        await store.addLedger('notifications', LedgerAction.read, count: i);
      }
      await tester.pumpAndSettle();
      expect(find.textContaining('Read '), findsNWidgets(8));
      await tester.tap(_key('ledger-clear'));
      await tester.pumpAndSettle();
      expect(find.textContaining('does not delete any data'), findsOneWidget);
      await tester.tap(_key('ledger-clear-confirm'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Read '), findsNothing);
      expect(find.textContaining('The ledger is empty'), findsOneWidget);
      expect(await store.ledger(), isEmpty);
    });
  });
}
