/// Read-only Gmail (0.7b). Signs in with the user's own Google account
/// (`gmail.readonly` only), reads the last [gmailWindow] of the INBOX (at most
/// [maxGmailThreads] threads) and keeps ONE item per thread, built from its
/// newest message: sender, subject, date, labels and the plain-text body cut to
/// 8 KB. Mail goes into the local store and index only.
///
/// Privacy rules, all enforced here or in the store:
///  * Mail text is untrusted. Ask, the Inbox summaries and Today reach a prompt
///    only through the `<sources>` block (`sources_block.dart`). The one other
///    route is the user-tapped "Draft reply": it puts the mail text in the
///    `<text>` block of an action chat (`wrapActionText`, which strips every
///    `<text>` tag variant from it), as quoted material under a fixed
///    instruction. It is not the `<sources>` path, and its output only ever
///    becomes a draft the user copies; nothing is sent or run.
///  * A message that looks like a verification code is stored with its text
///    replaced (`looksLikeMailCode`): the code is gone before anything is
///    written.
///  * Every sync writes a "Read N emails" ledger row (`BaseConnector`).
///  * No token is stored by us. The source asks Google for one silently on each
///    sync; if that needs the user, the connector goes to Needs attention
///    ("Reconnect Gmail"). Testing mode expires the grant every 7 days. A
///    background (headless) run that cannot ask silently just skips.
///  * Revoke deletes every local item (bounded waits, so a hung Google call
///    cannot block it), signs out and asks Google to revoke the grant. If Google cannot confirm, [remoteRevokeConfirmed] is
///    false and the UI tells the user to finish at myaccount.google.com.
///
/// Google's Limited Use rule for restricted scopes: mail text is used only for
/// features the user sees (Inbox, Ask, Today). It is never sent anywhere, never
/// logged, and used for no analytics or model training; the app has no
/// telemetry at all.
library;

import '../../core/identity/app_identity.dart';
import 'base_connector.dart';
import 'connector.dart';
import 'connector_sources.dart';
import 'connector_store.dart' show ConnectorAccount, ConnectorStore, capText;
import 'otp_guard.dart';

/// How far back a sync reads.
const gmailWindow = Duration(days: 7);

/// Most threads one sync keeps.
const maxGmailThreads = 200;

/// Stored-text caps, applied to whatever a source returns.
const maxMailSubjectChars = 300;
const maxMailNameChars = 200;
const maxMailEmailChars = 254;

class GmailConnector extends BaseConnector {
  GmailConnector({required ConnectorStore store, required this.source})
    : super(store);

  final GmailSource source;

  /// Set by the background (headless) sync: no Activity there, so Google
  /// cannot be asked even silently. A run that cannot authenticate then skips
  /// quietly instead of marking the connector "Needs attention".
  bool headless = false;

  /// Whether the last [revoke] confirmed the grant is gone at Google. Null
  /// before any revoke.
  bool? remoteRevokeConfirmed;

  @override
  String get id => ConnectorIds.mail;

  @override
  String get displayName => 'Gmail';

  static const reconnect =
      'Google needs you to sign in again. Reconnect Gmail to keep your mail '
      'current.';

  /// Said to the user when the grant could not be revoked at Google.
  static final finishAtGoogle =
      'Removed from this phone. To finish, remove ${AppIdentity.shortName} at '
      'myaccount.google.com/permissions.';

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
    final GmailFetch fetch;
    try {
      fetch = await source.recentThreads(
        since: from,
        maxThreads: maxGmailThreads,
      );
    } on GmailAuthException {
      if (headless) {
        return const SyncResult.skipped('Gmail updates when you open the app.');
      }
      throw const ConnectorException(ConnectorState.needsAttention, reconnect);
    }
    // Revoke asked for while the read ran: write nothing.
    if (syncCancelled) return const SyncResult.skipped('Disconnected.');
    // The source is asked for the window and the cap, but a misbehaving one
    // must not widen either.
    final threads = fetch.threads;
    final drafts = <ItemDraft>[];
    for (final t in threads.take(maxGmailThreads)) {
      final d = _draft(t, from);
      if (d != null) drafts.add(d);
    }
    final result = await store.upsertItems(id, drafts, requireAccount: true);
    if (syncCancelled) return const SyncResult.skipped('Disconnected.');
    // Threads that left the window or the inbox leave the store, but only when
    // the listing is known complete: a page cut at the cap, or a thread that
    // failed to read, proves nothing about what is missing. Age always removes.
    if (fetch.complete && threads.length <= maxGmailThreads) {
      final keep = {for (final t in threads) t.id};
      await store.removeByExternalIds(id, [
        for (final i in await store.flagsOf(id, ItemKind.mail))
          if (!keep.contains(i.externalId)) i.externalId,
      ]);
    }
    if (syncCancelled) return const SyncResult.skipped('Disconnected.');
    await store.pruneOlderThan(id, from);
    return SyncResult(read: drafts.length, changed: result.changed);
  }

  ItemDraft? _draft(GmailThread t, DateTime from) {
    if (t.messages.isEmpty) return null;
    final m = t.messages.reduce((a, b) => b.date.isAfter(a.date) ? b : a);
    if (m.date.isBefore(from)) return null;
    final subject = capText(m.subject, maxMailSubjectChars);
    final text = capText(m.text, maxItemBodyChars);
    final from0 = m.from;
    final person = from0 == null
        ? null
        : Person(
            name: from0.name == null
                ? null
                : capText(from0.name!, maxMailNameChars),
            email: from0.email == null
                ? null
                : capText(from0.email!, maxMailEmailChars),
          );
    final code = looksLikeMailCode(subject, text);
    final sender = person?.name ?? person?.email ?? 'Gmail';
    return ItemDraft(
      externalId: t.id,
      kind: ItemKind.mail,
      // The subject may carry the code too, so the sender stands in for it.
      title: code ? sender : subject,
      body: code ? hiddenCodeBody : text,
      people: [?person],
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
        if (t.messageCount > 1) 'messages': t.messageCount,
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
  Future<void> onRevoke(ConnectorAccount? account) async {
    // Never throws and never hangs the wipe: the base also bounds this call,
    // and a bound that fires leaves this false.
    remoteRevokeConfirmed = false;
    try {
      remoteRevokeConfirmed = await source.signOut();
    } catch (_) {
      remoteRevokeConfirmed = false;
    }
  }

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
