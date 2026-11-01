/// Read-only contacts connector. It never reads the address book as a whole:
/// it collects the email addresses of people who already appear in synced
/// events, mail or notifications and asks the OS about those people only, so
/// Today can show a name and an avatar instead of an address.
library;

import 'dart:convert';

import 'base_connector.dart';
import 'connector.dart';
import 'connector_sources.dart';
import 'connector_store.dart';

/// Most lookups one sync makes.
const maxContactLookups = 200;

/// Largest avatar kept in the store (bytes before base64).
const maxAvatarBytes = 24 * 1024;

class ContactsConnector extends BaseConnector {
  ContactsConnector({required ConnectorStore store, required this.source})
    : super(store);

  final ContactsSource source;

  @override
  String get id => ConnectorIds.contacts;

  @override
  String get displayName => 'Contacts';

  static const _off =
      'Contacts access is off. Open settings and allow Contacts so names '
      'and photos can show up next to your meetings.';

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

  /// Emails of everyone seen in other connectors' items, lowercased, oldest
  /// lookups last. Public for tests.
  Future<List<String>> emailsToResolve() async {
    final seen = <String>{};
    for (final source in [ConnectorIds.calendar, ConnectorIds.notifications]) {
      for (final item in await store.itemsOf(source)) {
        for (final p in item.people) {
          final e = p.email?.trim().toLowerCase();
          if (e != null && e.contains('@')) seen.add(e);
        }
      }
    }
    // ponytail: no negative cache; an address with no matching contact is
    // looked up again next sync. Add a miss-set if lookups ever get slow.
    return seen.take(maxContactLookups).toList();
  }

  @override
  Future<SyncResult> doSync(ConnectorAccount account, DateTime? since) async {
    if (await source.permission() != DevicePermission.granted) {
      throw const ConnectorException(ConnectorState.permissionDenied, _off);
    }
    final emails = await emailsToResolve();
    // One draft per contact; a contact reached by two addresses keeps both.
    final byContact = <String, ({DeviceContact c, List<String> emails})>{};
    for (final email in emails) {
      final DeviceContact? c;
      try {
        c = await source.byEmail(email);
      } catch (_) {
        throw const ConnectorException(
          ConnectorState.needsAttention,
          'Could not read your contacts. Pull to refresh to try again.',
        );
      }
      if (c == null || c.name.trim().isEmpty) continue;
      final key = c.id ?? 'email:$email';
      final entry = byContact[key];
      if (entry == null) {
        byContact[key] = (c: c, emails: [email]);
      } else {
        entry.emails.add(email);
      }
    }
    final drafts = [
      for (final e in byContact.entries)
        ItemDraft(
          externalId: e.key,
          kind: ItemKind.contact,
          title: e.value.c.name.trim(),
          people: [
            for (final m in e.value.emails)
              Person(name: e.value.c.name.trim(), email: m),
          ],
          flags: {
            if (e.value.c.thumbnail != null &&
                e.value.c.thumbnail!.isNotEmpty &&
                e.value.c.thumbnail!.length <= maxAvatarBytes)
              'photo': base64Encode(e.value.c.thumbnail!),
          },
        ),
    ];
    final result = await store.upsertItems(id, drafts, requireAccount: true);
    return SyncResult(read: drafts.length, changed: result.changed);
  }

  @override
  Future<void> openSystemSettings() => source.openSettings();
}
