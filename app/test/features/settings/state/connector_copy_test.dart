import 'package:dhruva/data/connectors/connector.dart';
import 'package:dhruva/features/settings/state/connector_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every connector has plain-words copy for what it reads and what '
      'disconnecting does', () {
    for (final id in ['calendar', 'contacts', 'folder', 'notifications']) {
      final c = copyFor(id);
      expect(c.reads, isNotEmpty, reason: id);
      expect(c.disconnectEffect, isNotEmpty, reason: id);
    }
    expect(
      copyFor('calendar').disconnectEffect,
      'Removes the copy of your events on this phone. Your calendar itself is '
      'untouched.',
    );
    // The folder grant is released by the app, so there is no OS page to
    // offer; the others hold an OS permission.
    expect(copyFor('folder').hasOsPermission, isFalse);
    for (final id in ['calendar', 'contacts', 'notifications']) {
      expect(copyFor(id).hasOsPermission, isTrue, reason: id);
    }
  });

  group('statusLine', () {
    String when(DateTime d) => '7:01';
    test('each state reads plainly and carries its tone', () {
      expect(
        statusLine(ConnectorStatus.notConnected, when: when).label,
        'Not connected',
      );
      expect(
        statusLine(
          ConnectorStatus(
            ConnectorState.connected,
            lastSyncAt: DateTime(2026, 11, 1, 7, 1),
          ),
          when: when,
        ).label,
        'Connected · synced 7:01',
      );
      expect(
        statusLine(
          const ConnectorStatus(ConnectorState.connected),
          when: when,
        ).label,
        'Connected',
      );
      expect(
        statusLine(
          const ConnectorStatus(ConnectorState.syncing),
          when: when,
        ).tone,
        StatusTone.ok,
      );
      for (final s in [
        ConnectorState.needsAttention,
        ConnectorState.permissionDenied,
      ]) {
        expect(
          statusLine(ConnectorStatus(s), when: when).tone,
          StatusTone.attention,
        );
        expect(needsFix(ConnectorStatus(s)), isTrue);
      }
      expect(needsFix(ConnectorStatus.notConnected), isFalse);
    });
  });

  group('ledger sentences', () {
    LedgerEntry e(String c, String a, int n) =>
        LedgerEntry(connector: c, action: a, count: n, at: DateTime(2026));
    test('titles and sources', () {
      expect(ledgerTitle(e('calendar', 'read', 4)), 'Read 4 events');
      expect(ledgerTitle(e('calendar', 'read', 1)), 'Read 1 event');
      expect(ledgerTitle(e('folder', 'read', 12)), 'Read 12 files');
      expect(ledgerTitle(e('contacts', 'read', 2)), 'Read 2 people');
      expect(
        ledgerTitle(e('notifications', 'read', 7)),
        'Read 7 notifications',
      );
      expect(ledgerTitle(e('calendar', 'connect', 0)), 'Connected');
      expect(
        ledgerTitle(e('calendar', 'revoke', 0)),
        'Disconnected and deleted the copy',
      );
      expect(ledgerTitle(e('calendar', 'failed', 0)), 'Could not read');
      expect(ledgerSource(e('folder', 'read', 1)), 'Notes folder');
    });

    test('times: clock today, Yesterday, weekday, date', () {
      final now = DateTime(2026, 11, 2, 12);
      String clock(DateTime d) => '7:01';
      expect(ledgerWhen(DateTime(2026, 11, 2, 7, 1), now, clock), '7:01');
      expect(ledgerWhen(DateTime(2026, 11, 1, 23), now, clock), 'Yesterday');
      expect(ledgerWhen(DateTime(2026, 10, 31, 9), now, clock), 'Sat');
      expect(ledgerWhen(DateTime(2026, 10, 20, 9), now, clock), '20 Oct');
    });
  });
}
