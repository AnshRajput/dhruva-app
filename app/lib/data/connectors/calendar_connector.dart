/// Read-only calendar connector: events from the next 14 days and the last day,
/// across every calendar the user has not switched off (`config.excluded`).
/// Nothing is ever written back to the calendar (adding an event goes through
/// the OS insert screen, not through here).
library;

import 'base_connector.dart';
import 'connector.dart';
import 'connector_sources.dart';
import 'connector_store.dart';

/// How far the window reaches.
const calendarDaysAhead = 14;
const calendarDaysBack = 1;

class CalendarConnector extends BaseConnector {
  CalendarConnector({required ConnectorStore store, required this.source})
    : super(store);

  final CalendarSource source;

  @override
  String get id => ConnectorIds.calendar;

  @override
  String get displayName => 'Calendar';

  static const _off =
      'Calendar access is off. Open settings and allow Calendar to bring '
      'your events back.';

  @override
  Future<ConnectorStatus> evaluate(ConnectorAccount? account) async {
    if (account == null) return ConnectorStatus.notConnected;
    if (await source.permission() != DevicePermission.granted) {
      return ConnectorStatus(
        ConnectorState.permissionDenied,
        detail: _off,
        lastSyncAt: account.lastSyncAt,
      );
    }
    if (account.lastError != null) {
      return ConnectorStatus(
        ConnectorState.needsAttention,
        detail: account.lastError,
        lastSyncAt: account.lastSyncAt,
      );
    }
    return ConnectorStatus(
      ConnectorState.connected,
      lastSyncAt: account.lastSyncAt,
    );
  }

  @override
  Future<ConnectorStatus> doConnect() async {
    var p = await source.permission();
    if (p != DevicePermission.granted) p = await source.request();
    if (p != DevicePermission.granted) {
      return const ConnectorStatus(
        ConnectorState.permissionDenied,
        detail: _off,
      );
    }
    await store.saveAccount(id, status: 'connected', clearError: true);
    return ConnectorStatus(
      ConnectorState.connected,
      lastSyncAt: (await store.account(id))?.lastSyncAt,
    );
  }

  @override
  Future<SyncResult> doSync(ConnectorAccount account, DateTime? since) async {
    if (await source.permission() != DevicePermission.granted) {
      throw const ConnectorException(ConnectorState.permissionDenied, _off);
    }
    final now = store.now;
    final from = now.subtract(const Duration(days: calendarDaysBack));
    final to = now.add(const Duration(days: calendarDaysAhead));
    final List<DeviceCalendarEvent> events;
    try {
      events = await source.events(from, to);
    } catch (_) {
      // No prune below: a failed read must never look like "all events gone".
      throw const ConnectorException(
        ConnectorState.needsAttention,
        'Could not read your calendar. Pull to refresh to try again.',
      );
    }
    final excluded = {
      for (final c in (account.config['excluded'] as List?) ?? const [])
        if (c is String) c,
    };
    final drafts = [
      for (final e in events)
        if (!excluded.contains(e.calendarId)) _draft(e),
    ];
    final result = await store.upsertItems(id, drafts, requireAccount: true);
    await store.removeMissingInWindow(
      id,
      ItemKind.event,
      from: from,
      to: to,
      keep: {for (final d in drafts) d.externalId},
    );
    return SyncResult(read: drafts.length, changed: result.changed);
  }

  ItemDraft _draft(DeviceCalendarEvent e) {
    final body = [
      if (e.location != null && e.location!.trim().isNotEmpty)
        'Location: ${e.location!.trim()}',
      if (e.description != null && e.description!.trim().isNotEmpty)
        e.description!.trim(),
    ].join('\n');
    return ItemDraft(
      externalId: e.id,
      kind: ItemKind.event,
      title: e.title.trim().isEmpty ? '(No title)' : e.title.trim(),
      body: body,
      people: e.attendees,
      startsAt: e.start,
      flags: {
        'end': e.end.millisecondsSinceEpoch,
        'allDay': e.allDay,
        'recurring': e.recurring,
        'calendarId': e.calendarId,
        if (e.calendarName != null) 'calendar': e.calendarName,
        if (e.location != null) 'location': e.location,
      },
    );
  }

  /// Calendars the user turned off (by id), persisted in the account config.
  Future<void> setExcludedCalendars(List<String> calendarIds) async {
    final account = await store.account(id);
    if (account == null) return;
    await store.saveAccount(
      id,
      config: {...account.config, 'excluded': calendarIds},
    );
  }

  @override
  Future<void> openSystemSettings() => source.openSettings();
}
