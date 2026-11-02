/// The words and icons of the Connectors screen: per connector what it reads
/// (plain words), what disconnecting does, what the buttons say; plus the
/// status line and the privacy-ledger sentences. Pure, so tests pin the copy.
///
/// Icons are only ones already used elsewhere in the app (the tree-shaken icon
/// font cannot gain glyphs through a Shorebird patch).
library;

import 'package:flutter/material.dart';

import '../../../data/connectors/connector.dart';

final class ConnectorCopy {
  final IconData icon;
  final String name;

  /// What it can read, in plain words (shown on the row and in the sheet).
  final String reads;

  /// What Disconnect does (shown in the confirmation, before anything happens).
  final String disconnectEffect;

  /// Button label when not connected.
  final String connectLabel;

  /// Button label on the "Needs attention" card.
  final String fixLabel;

  /// Whether the OS holds a permission we cannot revoke ourselves, so the
  /// confirmation offers "Open system settings".
  final bool hasOsPermission;

  const ConnectorCopy({
    required this.icon,
    required this.name,
    required this.reads,
    required this.disconnectEffect,
    required this.connectLabel,
    required this.fixLabel,
    required this.hasOsPermission,
  });
}

const _copy = <String, ConnectorCopy>{
  ConnectorIds.calendar: ConnectorCopy(
    icon: Icons.calendar_today_outlined,
    name: 'Calendar',
    reads:
        'Event titles, times, places and who is invited. It never changes '
        'your calendar.',
    disconnectEffect:
        'Removes the copy of your events on this phone. Your calendar itself '
        'is untouched.',
    connectLabel: 'Connect',
    fixLabel: 'Reconnect',
    hasOsPermission: true,
  ),
  ConnectorIds.contacts: ConnectorCopy(
    icon: Icons.people_outline,
    name: 'Contacts',
    reads:
        'Names and photos of the people who show up in your events. Nothing '
        'is changed or uploaded.',
    disconnectEffect:
        'Removes the copy on this phone. Your contacts themselves are '
        'untouched.',
    connectLabel: 'Connect',
    fixLabel: 'Reconnect',
    hasOsPermission: true,
  ),
  ConnectorIds.folder: ConnectorCopy(
    icon: Icons.folder_outlined,
    name: 'Notes folder',
    reads:
        'Text, Markdown and PDF files in the one folder you choose. Read '
        'only.',
    disconnectEffect:
        'Removes the search index of your files from this phone and lets go '
        'of the folder. Your files are untouched.',
    connectLabel: 'Choose folder',
    fixLabel: 'Choose again',
    hasOsPermission: false,
  ),
  ConnectorIds.notifications: ConnectorCopy(
    icon: Icons.notifications_none,
    name: 'Notifications',
    reads:
        'The title and text of notifications from your apps, kept for 7 days. '
        'Private notifications are skipped and verification codes are hidden.',
    disconnectEffect:
        'Deletes the notifications saved on this phone and stops listening. '
        'To fully revoke it, also switch off notification access in system '
        'settings.',
    connectLabel: 'Turn on',
    fixLabel: 'Turn on access',
    hasOsPermission: true,
  ),
};

ConnectorCopy copyFor(String connectorId) =>
    _copy[connectorId] ??
    ConnectorCopy(
      icon: Icons.link_outlined,
      name: connectorId,
      reads: 'Data you choose to connect.',
      disconnectEffect: 'Removes the copy on this phone.',
      connectLabel: 'Connect',
      fixLabel: 'Reconnect',
      hasOsPermission: false,
    );

/// "7:01" or "7:01 PM", following the phone's 12/24 hour setting.
String clockText(BuildContext context, DateTime at) => MaterialLocalizations.of(
  context,
).formatTimeOfDay(TimeOfDay.fromDateTime(at));

/// How a status reads: the label and which colour family it uses.
enum StatusTone { ok, attention, off }

final class StatusLine {
  final String label;
  final StatusTone tone;
  const StatusLine(this.label, this.tone);
}

/// "Connected · Synced 7:01", "Needs attention", "Not connected" ...
StatusLine statusLine(
  ConnectorStatus s, {
  required String Function(DateTime) when,
}) {
  switch (s.state) {
    case ConnectorState.connected:
      final at = s.lastSyncAt;
      return StatusLine(
        at == null ? 'Connected' : 'Connected · synced ${when(at)}',
        StatusTone.ok,
      );
    case ConnectorState.syncing:
      return const StatusLine('Connected · reading now', StatusTone.ok);
    case ConnectorState.permissionDenied:
      return const StatusLine('Access is off', StatusTone.attention);
    case ConnectorState.needsAttention:
      return const StatusLine('Needs attention', StatusTone.attention);
    case ConnectorState.notConnected:
    case ConnectorState.unsupported:
      return const StatusLine('Not connected', StatusTone.off);
  }
}

/// True when the row should be promoted to the attention card.
bool needsFix(ConnectorStatus s) =>
    s.state == ConnectorState.needsAttention ||
    s.state == ConnectorState.permissionDenied;

// ---- privacy ledger --------------------------------------------------------

String _noun(String connector, int n) {
  final one = n == 1;
  return switch (connector) {
    ConnectorIds.calendar => one ? 'event' : 'events',
    ConnectorIds.contacts => one ? 'person' : 'people',
    ConnectorIds.folder => one ? 'file' : 'files',
    ConnectorIds.notifications => one ? 'notification' : 'notifications',
    _ => one ? 'item' : 'items',
  };
}

/// "Read 4 events", "Connected", "Could not read" ...
String ledgerTitle(LedgerEntry e) => switch (e.action) {
  LedgerAction.read => 'Read ${e.count} ${_noun(e.connector, e.count)}',
  LedgerAction.connect => 'Connected',
  LedgerAction.revoke => 'Disconnected and deleted the copy',
  LedgerAction.failed => 'Could not read',
  _ => e.action,
};

String ledgerSource(LedgerEntry e) => copyFor(e.connector).name;
