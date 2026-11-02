/// The `/ask/new` route contract: a fresh Ask thread, optionally prefilled and
/// with sources pinned. Today's "Prep me for `<event>`" (and anything else that
/// wants to start a grounded question) calls [askNewLocation] and pushes the
/// result:
///
/// ```dart
/// context.push(
///   askNewLocation(
///     q: 'Prep me for Budget review',
///     sources: {AskSource.calendar, AskSource.contacts, AskSource.files},
///   ),
/// );
/// ```
///
/// * `q`: text placed in the composer. It is NOT sent: the user reads it, sees
///   the pinned sources and taps send.
/// * `focus`: connector item id(s) this thread is ABOUT (repeatable); how
///   Library "Ask about this file" and Inbox "Ask about this" start a thread.
///   Their text leads the sources block; the thread opens with no Auto, only
///   the `sources` pinned (none for the Library and Inbox entry points).
/// * `about`: a short label (a person's name) this thread is ABOUT. It is
///   untrusted text (an invite author chose it): sanitized by
///   [sanitizeAskAbout], used only as a retrieval term and a chip, and shown
///   to the model inside the quoted sources block, never in the question.
/// * `sources`: comma-separated `calendar,contacts,files,mail,docs`; those
///   chips arrive pinned (Auto off). Unknown ids are ignored; missing or empty
///   means Auto.
///
/// `/ask/new` is a full-screen route outside the shell, so callers `push` it.
/// The Ask TAB (the plain `/ask` shell branch) is never pushed; see
/// `app_router.dart`.
library;

import '../../data/connectors/ask_sources.dart';

/// `/ask/new?q=...&sources=calendar,contacts,files`. Both parameters are
/// optional and URL-encoded.
String askNewLocation({
  String? q,
  Iterable<AskSource> sources = const [],
  Iterable<int> focus = const [],
  String? about,
}) {
  final params = <String, Object>{
    if (q != null && q.trim().isNotEmpty) 'q': q,
    if (sources.isNotEmpty)
      'sources': [
        for (final s in AskSource.values)
          if (sources.contains(s)) s.name,
      ].join(','),
    if (focus.isNotEmpty) 'focus': [for (final i in focus) '$i'],
    if (sanitizeAskAbout(about) != null) 'about': sanitizeAskAbout(about)!,
  };
  return Uri(
    path: '/ask/new',
    queryParameters: params.isEmpty ? null : params,
  ).toString();
}

/// Longest `about` label kept.
const maxAskAboutChars = 80;

/// Control characters (newlines and tabs included) become spaces, whitespace
/// collapses, the result is cut to [maxAskAboutChars] without splitting a
/// surrogate pair. Null when nothing is left.
String? sanitizeAskAbout(String? raw) {
  if (raw == null) return null;
  var s = raw
      .replaceAll(RegExp(r'[\u0000-\u001F\u007F-\u009F\u2028\u2029]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (s.length > maxAskAboutChars) {
    var end = maxAskAboutChars;
    final last = s.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end--;
    s = s.substring(0, end).trimRight();
  }
  return s.isEmpty ? null : s;
}

/// Longest prefill carried in the URL; anything longer is cut (a deep route
/// is not a document channel).
const maxAskPrefillChars = 2000;

/// Reads `q` / `sources` back out of a route's query parameters.
({String? draft, Set<AskSource> sources, List<int> focus, String? about})
parseAskNewQuery(
  Map<String, String> query, {
  Iterable<String> focus = const [],
}) {
  final q = query['q']?.trim();
  return (
    focus: [for (final s in focus) ?int.tryParse(s)],
    draft: q == null || q.isEmpty
        ? null
        : (q.length <= maxAskPrefillChars
              ? q
              : q.substring(0, maxAskPrefillChars)),
    sources: parseAskSources(query['sources']),
    about: sanitizeAskAbout(query['about']),
  );
}
