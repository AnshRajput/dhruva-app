/// Shared plumbing for the four device connectors: the status stream, the
/// opt-in row, and the guarantees every sync must keep (ledger row written,
/// failures recorded as "needs attention" with a sentence that names the fix,
/// revoke wipes the store). Subclasses only say what to read and how to ask the
/// OS for access.
library;

import 'dart:async';

import 'connector.dart';
import 'connector_store.dart';

abstract class BaseConnector implements Connector {
  BaseConnector(this.store) : _status = ConnectorStatus.notConnected;

  final ConnectorStore store;

  final _controller = StreamController<ConnectorStatus>.broadcast();
  ConnectorStatus _status;
  bool _syncing = false;
  Future<void>? _running;
  bool _cancelled = false;

  /// Called after [connect] and [revoke] finish (status already emitted). The
  /// hub sets it to keep the background job in step with what is connected.
  Future<void> Function()? onConnectionChanged;

  /// True once [revoke] has been asked for while a sync runs; long reads
  /// (the folder index) check it and stop.
  bool get syncCancelled => _cancelled;

  /// Asks a running sync to stop at its next checkpoint (the "Cancel" button
  /// on a manual folder index). What is already stored stays. No-op when
  /// nothing is running.
  void cancelSync() {
    if (_syncing) _cancelled = true;
  }

  @override
  Stream<ConnectorStatus> get status => _controller.stream;

  @override
  ConnectorStatus get currentStatus => _status;

  /// Sets [s] and notifies listeners if it changed.
  void emit(ConnectorStatus s) {
    if (s == _status) return;
    _status = s;
    if (!_controller.isClosed) _controller.add(s);
  }

  Future<void> dispose() => _controller.close();

  // ---- subclass surface ----------------------------------------------------

  /// Works out the status from the stored opt-in row and the OS. Never throws.
  Future<ConnectorStatus> evaluate(ConnectorAccount? account);

  /// Asks the OS for access and, when granted, records the opt-in (with
  /// [saveAccount]). Returns the status to show afterwards.
  Future<ConnectorStatus> doConnect();

  /// The read. Throw [ConnectorException] for anything the user can fix.
  Future<SyncResult> doSync(ConnectorAccount account, DateTime? since);

  /// Releases whatever the connector holds besides stored rows (folder grant,
  /// notification capture switch). Runs before the wipe; must not throw.
  Future<void> onRevoke(ConnectorAccount? account) async {}

  // ---- Connector -------------------------------------------------------------

  @override
  Future<void> refreshStatus() async {
    if (_syncing) return;
    emit(await _evaluateSafely(await store.account(id)));
  }

  Future<ConnectorStatus> _evaluateSafely(ConnectorAccount? account) async {
    try {
      return await evaluate(account);
    } catch (_) {
      return ConnectorStatus(
        ConnectorState.needsAttention,
        detail: 'Could not check $displayName. Try again.',
        lastSyncAt: account?.lastSyncAt,
      );
    }
  }

  @override
  Future<void> connect() async {
    final next = await doConnect();
    if (next.isConnected) {
      await store.addLedger(id, LedgerAction.connect);
    }
    emit(next);
    await onConnectionChanged?.call();
  }

  @override
  Future<SyncResult> sync({DateTime? since}) async {
    final account = await store.account(id);
    if (account == null) {
      throw ConnectorException(
        ConnectorState.notConnected,
        '$displayName is not connected.',
      );
    }
    _syncing = true;
    _cancelled = false;
    final done = Completer<void>();
    _running = done.future;
    emit(_status.copyWith(state: ConnectorState.syncing));
    try {
      final result = await doSync(account, since);
      if (result.skipped == null) {
        await store.recordSync(id, count: result.read);
      }
      emit(await _evaluateSafely(await store.account(id)));
      return result;
    } on ConnectorException catch (e) {
      await _recordFailure(e.message);
      emit(
        ConnectorStatus(
          e.state,
          detail: e.message,
          lastSyncAt: account.lastSyncAt,
        ),
      );
      rethrow;
    } catch (_) {
      final msg = 'Could not read $displayName. Try again.';
      await _recordFailure(msg);
      emit(
        ConnectorStatus(
          ConnectorState.needsAttention,
          detail: msg,
          lastSyncAt: account.lastSyncAt,
        ),
      );
      throw ConnectorException(ConnectorState.needsAttention, msg);
    } finally {
      _syncing = false;
      done.complete();
    }
  }

  Future<void> _recordFailure(String message) =>
      store.recordFailure(id, message);

  @override
  Future<void> revoke() async {
    // Stop a running sync and let it finish first. The store also refuses
    // late writes once the account row is gone, which is what protects against
    // a sync in another isolate (the background engine).
    final running = _running;
    if (_syncing && running != null) {
      _cancelled = true;
      try {
        await running;
      } catch (_) {}
    }
    final account = await store.account(id);
    try {
      await onRevoke(account);
    } catch (_) {
      // Releasing the OS-side handle is best effort; the local wipe below is
      // what the user asked for and always runs.
    }
    await store.wipeConnector(id);
    emit(ConnectorStatus.notConnected);
    await onConnectionChanged?.call();
  }
}
