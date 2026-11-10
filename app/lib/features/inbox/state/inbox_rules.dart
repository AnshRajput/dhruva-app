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

export '../../../data/connectors/needs_reply.dart'
    show hasPersonSender, needsReply, needsReplyIds, senderOf;

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
/// mail's subject, else the first line of the body.
String rowLineOf(ConnectorItem item) =>
    usableSummary(item) ??
    (item.kind == ItemKind.mail && item.title.trim().isNotEmpty
        ? item.title.trim()
        : firstLineOf(item.body));
