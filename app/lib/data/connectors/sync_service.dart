/// Runs the connectors in order and keeps one sync in flight at a time.
///
/// Triggers: app open ([syncOnOpen], skips connectors synced very recently),
/// manual refresh ([refresh], always runs) and the Android WorkManager job
/// (`background_sync.dart`, which calls [refresh] too). Every connector's own
/// `sync` writes its ledger row, so no trigger can skip the privacy ledger.
library;

import 'dart:async';

import 'connector.dart';

/// App-open syncs skip a connector that synced less than this long ago. It
/// guards the heavy reads (calendar, folder, contacts); notifications are
/// exempt because a drain is a cheap local file read and the user expects a
/// new notification to show up right away.
const syncOnOpenMinInterval = Duration(minutes: 10);

/// How one connector's run ended.
final class SyncOutcome {
  final SyncResult? result;
  final ConnectorException? error;
  const SyncOutcome.done(SyncResult this.result) : error = null;
  const SyncOutcome.failed(ConnectorException this.error) : result = null;

  bool get ok => error == null;
}

final class SyncReport {
  final Map<String, SyncOutcome> outcomes;
  const SyncReport(this.outcomes);

  bool get allOk => outcomes.values.every((o) => o.ok);
  int get totalRead =>
      outcomes.values.fold(0, (n, o) => n + (o.result?.read ?? 0));
}

class SyncService {
  SyncService({
    required Iterable<Connector> connectors,
    DateTime Function()? clock,
  }) : _connectors = {for (final c in connectors) c.id: c},
       _clock = clock ?? DateTime.now;

  final Map<String, Connector> _connectors;
  final DateTime Function() _clock;
  Future<SyncReport>? _running;
  Future<SyncOutcome?>? _draining;

  /// True while a sync is running.
  bool get isRunning => _running != null;

  /// On app open: a connector synced within [syncOnOpenMinInterval] is left
  /// alone, so reopening the app repeatedly does not re-read everything.
  Future<SyncReport> syncOnOpen() => _run(skipRecent: true);

  /// Manual refresh / background job: always syncs every connected source.
  Future<SyncReport> refresh() => _run(skipRecent: false);

  /// Moves what the notification listener queued into the store, now, whatever
  /// the 10-minute throttle says. Called on app resume, when the Inbox opens
  /// and on pull-to-refresh. Null when notifications are not connected. Shares
  /// a running drain or full sync instead of starting a second one.
  Future<SyncOutcome?> drainNotifications() {
    final draining = _draining;
    if (draining != null) return draining;
    final running = _running;
    final f = (running == null ? _drain() : running.then((_) => null))
        .whenComplete(() => _draining = null);
    _draining = f;
    return f;
  }

  Future<SyncOutcome?> _drain() async {
    final c = _connectors[ConnectorIds.notifications];
    if (c == null) return null;
    await c.refreshStatus();
    final state = c.currentStatus.state;
    if (state != ConnectorState.connected &&
        state != ConnectorState.needsAttention) {
      return null;
    }
    return _syncOne(c);
  }

  Future<SyncOutcome> _syncOne(Connector c) async {
    try {
      return SyncOutcome.done(await c.sync());
    } on ConnectorException catch (e) {
      return SyncOutcome.failed(e);
    } catch (_) {
      return SyncOutcome.failed(
        ConnectorException(
          ConnectorState.needsAttention,
          'Could not read ${c.displayName}. Try again.',
        ),
      );
    }
  }

  Future<SyncReport> _run({required bool skipRecent}) {
    // Single flight: a second caller shares the running sync.
    final running = _running;
    if (running != null) return running;
    final f = _syncAll(skipRecent).whenComplete(() => _running = null);
    _running = f;
    return f;
  }

  Future<SyncReport> _syncAll(bool skipRecent) async {
    final outcomes = <String, SyncOutcome>{};
    for (final id in ConnectorIds.syncOrder) {
      final c = _connectors[id];
      if (c == null) continue;
      await c.refreshStatus();
      final status = c.currentStatus;
      // Needs-attention sources are retried too: the fix (access back on,
      // folder re-granted) is outside the app, and a retry clears the card.
      if (status.state != ConnectorState.connected &&
          status.state != ConnectorState.needsAttention) {
        continue;
      }
      final last = status.lastSyncAt;
      if (skipRecent &&
          id != ConnectorIds.notifications &&
          last != null &&
          _clock().difference(last) < syncOnOpenMinInterval) {
        continue;
      }
      outcomes[id] = await _syncOne(c);
    }
    return SyncReport(outcomes);
  }
}
