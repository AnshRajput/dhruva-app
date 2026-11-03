/// "Needs a reply": the one rule that decides which captured messages are a
/// person asking the user something. Shared by the Inbox (its "Needs reply"
/// section) and Today (the brief's "N messages need a reply" fact), so the two
/// always agree. Lives in `data/` because two features read it (ADR-002).
///
/// Pure functions over a stored [ConnectorItem]; the text is only inspected,
/// never followed.
library;

import 'connector.dart';
import 'otp_guard.dart' show otpFlag;

/// What an [InboxEntry] row needs, read out of the item's flags.
extension InboxItem on ConnectorItem {
  String get appLabel {
    final a = flags['app'];
    if (a is String && a.trim().isNotEmpty) return a.trim();
    final p = packageName;
    return p.isEmpty ? 'App' : p;
  }

  String get packageName => (flags['pkg'] as String?) ?? '';

  bool get isRead => flags['read'] == true;

  DateTime get when => sentAt ?? updatedAt;
}

/// Who the item is from. The notification title is the conversation or person
/// for chat and mail apps; when it is empty or only repeats the app name, the
/// app label is all there is.
String senderOf(ConnectorItem item) {
  final t = item.title.trim();
  if (t.isEmpty || t.toLowerCase() == item.appLabel.toLowerCase()) {
    return item.appLabel;
  }
  return t;
}

/// True when [senderOf] is a real sender, not just the posting app.
bool hasPersonSender(ConnectorItem item) =>
    senderOf(item).toLowerCase() != item.appLabel.toLowerCase();

final _personName = RegExp(
  r"^\p{Lu}[\p{L}'.\-]*(?:\s+\p{L}[\p{L}'.\-]*){0,2}$",
  unicode: true,
);

final _requestWords = RegExp(
  r'\b(?:please|pls|plz|can you|could you|would you|will you|need you|'
  r'need your|let me know|confirm|approve|ok to|okay to|send me|call me|'
  r'get back|reply|respond|waiting for|awaiting|remind me|sign off|'
  r'your thoughts|your ok|your okay)\b',
  caseSensitive: false,
);

/// Money and marketing text is addressed to everyone, not asking you.
final _bulk = RegExp(
  r'\b(?:debited|credited|otp|cashback|discount|coupon|unsubscribe|'
  r'out for delivery|statement)\b|% off',
  caseSensitive: false,
);

/// A message from a person that is asking you something and is still unread.
/// [knownContacts] are lower-cased contact names.
bool needsReply(ConnectorItem item, {Set<String> knownContacts = const {}}) {
  if (item.flags[otpFlag] == true || item.isRead) return false;
  final sender = senderOf(item);
  final known = knownContacts.contains(sender.toLowerCase());
  final person =
      known || (hasPersonSender(item) && _personName.hasMatch(sender));
  if (!person) return false;
  final text = item.body;
  if (!known && _bulk.hasMatch(text)) return false;
  return text.contains('?') || _requestWords.hasMatch(text);
}

/// Ids of the items in [items] that need a reply.
Set<int> needsReplyIds(
  Iterable<ConnectorItem> items, {
  Set<String> knownContacts = const {},
}) => {
  for (final i in items)
    if (needsReply(i, knownContacts: knownContacts)) i.id,
};
