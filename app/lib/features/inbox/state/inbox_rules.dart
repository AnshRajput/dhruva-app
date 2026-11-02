/// Plain rules the Inbox applies on top of what is stored, so a small model's
/// wording or a messy notification never reaches the row as-is:
///
///  - [isMetaSummary]: a one-line summary that narrates the notification
///    ("The text is a notification from a phone...") instead of saying what it
///    is about is rejected; the row shows the first line of the body instead.
///  - [senderOf]: who the row is from (the notification's conversation title or
///    person), not the app that posted it.
///  - [needsReply]: a message from a person that asks something (a question
///    mark, a request verb, or a known contact) and is still unread.
///
/// Everything here is a pure function over a stored [ConnectorItem]; the text
/// is only inspected, never followed.
library;

import '../../../data/connectors/connector.dart';
import '../../../data/connectors/otp_guard.dart' show otpFlag;
import 'inbox_grouping.dart';

final _metaStart = RegExp(
  r'^(?:'
  r'(?:the|this|a|an)\s+(?:text|notification|message|alert|sms|email|mail|'
  r'content|update|snippet|push|post|screenshot|image)\b'
  r'|(?:market|notification|phone|device|app)\s+(?:data|content|text|alert)\b'
  r"|(?:the\s+)?user(?:'s)?\b"
  r'|(?:it|there)\s+(?:is|was|seems)\b'
  r"|here(?:'s|\s+is|\s+are)\b"
  r'|(?:sure|certainly|of\s+course|okay|ok)\b'
  r'|(?:summary|one-line summary)\s*:'
  r'|notification\s+(?:from|about)\b'
  r'|message\s+from\b'
  r')',
  caseSensitive: false,
);

final _metaAnywhere = RegExp(
  r"from the user'?s phone|notification from a phone|"
  r'is a notification\b|this notification\b|the notification (?:is|says)\b',
  caseSensitive: false,
);

/// True when [summary] describes the notification instead of the message.
bool isMetaSummary(String summary) {
  final s = summary.trim().replaceAll(RegExp(r'''^["'`*_\s]+'''), '');
  if (s.length < 4) return true;
  return _metaStart.hasMatch(s) || _metaAnywhere.hasMatch(s);
}

/// The summary worth showing, or null (none yet, or a meta-narrating one).
String? usableSummary(ConnectorItem item) {
  final s = item.summary?.trim();
  if (s == null || s.isEmpty || isMetaSummary(s)) return null;
  return s;
}

/// First non-empty line of the original text, whitespace tidied.
String firstLineOf(String body) {
  for (final l in body.split('\n')) {
    final t = l.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isNotEmpty) return t;
  }
  return '';
}

/// The one line a row shows under the sender: a usable summary, else the
/// first line of the body.
String rowLineOf(ConnectorItem item) =>
    usableSummary(item) ?? firstLineOf(item.body);

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
