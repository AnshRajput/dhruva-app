/// Read-only Gmail (0.7b). Signs in with the user's own Google account
/// (`gmail.readonly` only), reads the last [gmailWindow] of the INBOX (at most
/// [maxGmailThreads] threads) and keeps ONE item per thread, built from its
/// newest message: sender, subject, date, labels and the plain-text body cut to
/// 8 KB. Mail goes into the local store and index only.
///
/// Privacy rules, all enforced here or in the store:
///  * Mail text is untrusted. It reaches a prompt only through the
///    `<sources>` block (`sources_block.dart`).
///  * A message that looks like a verification code is stored with its text
///    replaced (`otp_guard.dart`), exactly like a notification: the code is gone
///    before anything is written.
///  * Every sync writes a "Read N emails" ledger row (`BaseConnector`).
///  * No token is stored by us. The source asks Google for one silently on each
///    sync; if that needs the user, the connector goes to Needs attention
///    ("Reconnect Gmail"). Testing mode expires the grant every 7 days.
///  * Revoke signs out (revoking the grant at Google) and deletes every item.
///
/// Google's Limited Use rule for restricted scopes: mail text is used only for
/// features the user sees (Inbox, Ask, Today). It is never sent anywhere, never
/// logged, and used for no analytics or model training; the app has no
/// telemetry at all.
library;

import 'base_connector.dart';
import 'connector.dart';
import 'connector_sources.dart';
import 'connector_store.dart' show ConnectorAccount, ConnectorStore, capText;
import 'otp_guard.dart';

/// How far back a sync reads.
const gmailWindow = Duration(days: 7);

/// Most threads one sync keeps.
const maxGmailThreads = 200;

class GmailConnector extends BaseConnector {
  GmailConnector({required ConnectorStore store, required this.source})
    : super(store);

  final GmailSource source;

  @override
  String get id => ConnectorIds.mail;

  @override
  String get displayName => 'Gmail';

  static const reconnect =
      'Google needs you to sign in again. Reconnect Gmail to keep your mail '
      'current.';

  @override
  ConnectorStatus get currentStatus =>
      source.configured ? super.currentStatus : ConnectorStatus.unsupported;

  @override
  Future<ConnectorStatus> evaluate(ConnectorAccount? account) async {
    if (!source.configured) return ConnectorStatus.unsupported;
    if (account == null) return ConnectorStatus.notConnected;
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
    if (!source.configured) return ConnectorStatus.unsupported;
    final String? email;
    try {
      email = await source.signIn();
    } on GmailAuthException catch (e) {
      return ConnectorStatus(ConnectorState.needsAttention, detail: e.message);
    } catch (_) {
      return const ConnectorStatus(
        ConnectorState.needsAttention,
        detail: 'Could not sign in to Google. Try again.',
      );
    }
    if (email == null) {
      backedOut = true;
      final existing = await store.account(id);
      return existing == null
          ? ConnectorStatus.notConnected
          : evaluate(existing);
    }
    await store.saveAccount(
      id,
      status: 'connected',
      label: email,
      config: const {},
      clearError: true,
    );
    return evaluate(await store.account(id));
  }

  @override
  Future<SyncResult> doSync(ConnectorAccount account, DateTime? since) async {
    final from = store.now.subtract(gmailWindow);
    final List<GmailThread> threads;
    try {
      threads = await source.recentThreads(
        since: from,
        maxThreads: maxGmailThreads,
      );
    } on GmailAuthException {
      throw const ConnectorException(ConnectorState.needsAttention, reconnect);
    }
    // The source is asked for the window and the cap, but a misbehaving one
    // must not widen either.
    final drafts = <ItemDraft>[];
    for (final t in threads.take(maxGmailThreads)) {
      final d = _draft(t, from);
      if (d != null) drafts.add(d);
    }
    final result = await store.upsertItems(id, drafts, requireAccount: true);
    // Threads that left the window or the inbox leave the store. A listing cut
    // off at the cap proves nothing about what is missing, so then only age
    // removes.
    if (threads.length < maxGmailThreads) {
      final keep = {for (final d in drafts) d.externalId};
      await store.removeByExternalIds(id, [
        for (final i in await store.flagsOf(id, ItemKind.mail))
          if (!keep.contains(i.externalId)) i.externalId,
      ]);
    }
    await store.pruneOlderThan(id, from);
    return SyncResult(read: drafts.length, changed: result.changed);
  }

  ItemDraft? _draft(GmailThread t, DateTime from) {
    if (t.messages.isEmpty) return null;
    final m = t.messages.reduce((a, b) => b.date.isAfter(a.date) ? b : a);
    if (m.date.isBefore(from)) return null;
    final code = looksLikeVerificationCode(m.subject, m.text);
    final sender = m.from?.name ?? m.from?.email ?? 'Gmail';
    return ItemDraft(
      externalId: t.id,
      kind: ItemKind.mail,
      // The subject may carry the code too, so the sender stands in for it.
      title: code ? sender : m.subject,
      body: code ? hiddenCodeBody : capText(m.text, maxItemBodyChars),
      people: [?m.from],
      sentAt: m.date,
      flags: {
        'pkg': ConnectorIds.mail,
        'app': 'Gmail',
        'messageId': m.id,
        'read': !m.labels.contains('UNREAD'),
        if (m.labels.contains('IMPORTANT')) 'important': true,
        // Gmail's own tabs: promotions, social, updates, forums.
        if (m.labels.any(_bulkLabels.contains)) 'bulk': true,
        if (m.labels.contains('SENT')) 'fromMe': true,
        if (t.messages.length > 1) 'messages': t.messages.length,
        if (code) otpFlag: true,
      },
    );
  }

  static const _bulkLabels = {
    'CATEGORY_PROMOTIONS',
    'CATEGORY_SOCIAL',
    'CATEGORY_UPDATES',
    'CATEGORY_FORUMS',
  };

  @override
  Future<void> onRevoke(ConnectorAccount? account) => source.signOut();

  /// Gmail has no OS permission page: the grant lives in the Google account.
  @override
  Future<void> openSystemSettings() async {}
}

/// Where "Open in Gmail" goes: the thread in Gmail's own web page (the Gmail
/// app claims this link on a phone that has it). A user-tapped hand-off; the
/// thread id is the connector's own item id, never mail text.
Uri gmailThreadUrl(String threadId) => Uri(
  scheme: 'https',
  host: 'mail.google.com',
  path: '/mail/u/0/',
  fragment: 'all/${Uri.encodeComponent(threadId)}',
);
