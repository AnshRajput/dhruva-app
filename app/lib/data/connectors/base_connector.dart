/// Shared plumbing for the four device connectors: the status stream, the
/// opt-in row, and the guarantees every sync must keep (ledger row written,
/// failures recorded as "needs attention" with a sentence that names the fix,
/// revoke wipes the store). Subclasses only say what to read and how to ask the
/// OS for access.
library;

import 'dart:async';

import 'connector.dart';
import 'connector_sources.dart' show DevicePermission;
import 'connector_store.dart';

abstract class BaseConnector implements Connector {
  BaseConnector(this.store) : _status = ConnectorStatus.notConnected;

  final ConnectorStore store;

  final _controller = StreamController<ConnectorStatus>.broadcast();
  ConnectorStatus _status;
  bool _syncing = false;
  Future<void>? _running;
  bool _cancelled = false;
  bool _connecting = false;
  ConnectorStatus _lastConnect = ConnectorStatus.notConnected;

  @override
  ConnectorStatus get lastConnectStatus => _lastConnect;

  /// A [doConnect] sets this when the user backed out of the OS UI (closed the
  /// folder picker): [connect] then records nothing and reports `false`.
  bool backedOut = false;

  /// True after a first-time connect ended in a permission the OS will not ask
  /// for again: the user was sent to system settings, and when the app comes
  /// back with the grant in place the hub completes the connection by itself.
  bool awaitingGrant = false;

  /// Whether the OS permission is in place right now (no prompt). Connectors
  /// with an in-app permission override it; the hub uses it for
  /// [awaitingGrant].
  Future<bool> grantedNow() async => false;

  /// The status after the OS permission prompt ended without a grant. Three
  /// different situations, three different sentences:
  ///  - connected before, access since turned off: [revoked] (a fix card);
  ///  - never connected, the prompt can still be shown (Android's first Deny):
  ///    [retry], the row stays "Not connected";
  ///  - never connected, denied for good: [blocked] plus "Open settings".
  ConnectorStatus deniedStatus(
    DevicePermission permission,
    ConnectorAccount? account, {
    required String retry,
    required String blocked,
    required String revoked,
  }) {
    if (account != null) {
      return ConnectorStatus(
        ConnectorState.permissionDenied,
        detail: revoked,
        lastSyncAt: account.lastSyncAt,
      );
    }
    final isFinal = permission == DevicePermission.denied;
    awaitingGrant = isFinal;
    return ConnectorStatus(
      ConnectorState.notConnected,
      detail: isFinal ? blocked : retry,
      needsSettings: isFinal,
    );
  }

  /// Called after [connect] and [revoke] finish (status already emitted). The
  /// hub sets it to keep the background job in step with what is connected.
  Future<void> Function()? onConnectionChanged;

  /// Called after [revoke] has wiped this connector's local data. The app sets
  /// it to drop derived copies of that data (the written Today brief), so text
  /// from a disconnected source never lingers. Must not throw (guarded).
  Future<void> Function()? onWiped;

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

  /// False for a source that is polled often (notifications): a read that
  /// found nothing then leaves no "Read 0" row in the privacy ledger.
  bool get logEmptyReads => true;

  /// Releases whatever the connector holds besides stored rows (folder grant,
  /// notification capture switch). Runs before the wipe; must not throw.
  Future<void> onRevoke(ConnectorAccount? account) async {}

  // ---- Connector -------------------------------------------------------------

  @override
  Future<void> refreshStatus() async {
    // Resume fires while the OS prompt closes: a refresh then would overwrite
    // the denial sentence connect() is about to emit.
    if (_syncing || _connecting) return;
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
  Future<bool> connect() async {
    backedOut = false;
    awaitingGrant = false;
    _connecting = true;
    final ConnectorStatus next;
    try {
      next = await doConnect();
    } finally {
      _connecting = false;
    }
    _lastConnect = next;
    if (backedOut) {
      // Nothing changed: no ledger row, no background-job churn. The status is
      // re-emitted only so a card that showed a spinner settles again.
      emit(next);
      return false;
    }
    if (next.isConnected) {
      await store.addLedger(id, LedgerAction.connect);
    }
    emit(next);
    await onConnectionChanged?.call();
    return true;
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
        await store.recordSync(
          id,
          count: result.read,
          ledger: result.read > 0 || logEmptyReads,
        );
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
    awaitingGrant = false;
    try {
      await onWiped?.call();
    } catch (_) {
      // Derived copies are best effort; the stored data is already gone.
    }
    emit(ConnectorStatus.notConnected);
    await onConnectionChanged?.call();
  }
}
