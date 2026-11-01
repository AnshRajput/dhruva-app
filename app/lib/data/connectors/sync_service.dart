/// Runs the connectors in order and keeps one sync in flight at a time.
///
/// Triggers: app open ([syncOnOpen], skips connectors synced very recently),
/// manual refresh ([refresh], always runs) and the Android WorkManager job
/// (`background_sync.dart`, which calls [refresh] too). Every connector's own
/// `sync` writes its ledger row, so no trigger can skip the privacy ledger.
library;

import 'dart:async';

import 'connector.dart';

/// App-open syncs skip a connector that synced less than this long ago.
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

  /// True while a sync is running.
  bool get isRunning => _running != null;

  /// On app open: a connector synced within [syncOnOpenMinInterval] is left
  /// alone, so reopening the app repeatedly does not re-read everything.
  Future<SyncReport> syncOnOpen() => _run(skipRecent: true);

  /// Manual refresh / background job: always syncs every connected source.
  Future<SyncReport> refresh() => _run(skipRecent: false);

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
          last != null &&
          _clock().difference(last) < syncOnOpenMinInterval) {
        continue;
      }
      try {
        outcomes[id] = SyncOutcome.done(await c.sync());
      } on ConnectorException catch (e) {
        outcomes[id] = SyncOutcome.failed(e);
      } catch (_) {
        outcomes[id] = SyncOutcome.failed(
          ConnectorException(
            ConnectorState.needsAttention,
            'Could not read ${c.displayName}. Try again.',
          ),
        );
      }
    }
    return SyncReport(outcomes);
  }
}
