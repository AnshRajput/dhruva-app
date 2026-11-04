/// Production [GmailSource]: `google_sign_in` 7.x for the account and the
/// silent `gmail.readonly` authorization, `googleapis` Gmail v1 for the reads.
///
/// Network: Google's sign-in services and https://gmail.googleapis.com. (On iOS
/// the GoogleSignIn SDK may also contact Google's own app-attestation
/// service; that is Google's SDK, not ours.) The Gmail client refuses any other
/// host and never follows a redirect. No token is stored by this app;
/// google_sign_in keeps its own credentials in the OS (Credential Manager on
/// Android, Keychain on iOS) and each sync asks for a short-lived access token
/// silently, holds it in a local variable for the duration of the sync and
/// drops it.
///
/// Everything read from Google is bounded here, before it reaches the store:
/// header values, MIME depth and part count, base64 decoded per part, message
/// size, request time. A thread that fails to read is skipped; it never fails
/// the whole sync.
///
/// Needs OAuth client ids from the build (`--dart-define`):
///   GMAIL_SERVER_CLIENT_ID  the Web client id (Android requires it)
///   GMAIL_IOS_CLIENT_ID     the iOS client id (iOS requires it)
/// With the id for the platform empty, [configured] is false and the connector
/// card never appears.
///
/// Platform glue: needs a real Google sign-in to exercise end to end. The
/// mapping from API objects and the bounded readers are pure and unit tested.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:http/http.dart' as http;

import 'connector.dart';
import 'connector_sources.dart';
import 'connector_store.dart' show capText;
import 'gmail_connector.dart'
    show maxMailEmailChars, maxMailNameChars, maxMailSubjectChars;

/// OAuth client ids baked in at build time.
final class GmailClientIds {
  const GmailClientIds({this.server = '', this.ios = ''});

  static const fromEnvironment = GmailClientIds(
    server: String.fromEnvironment('GMAIL_SERVER_CLIENT_ID'),
    ios: String.fromEnvironment('GMAIL_IOS_CLIENT_ID'),
  );

  final String server;
  final String ios;

  /// Whether this build can offer Gmail on [platform].
  bool supportedOn(TargetPlatform platform) => switch (platform) {
    TargetPlatform.android => server.isNotEmpty,
    TargetPlatform.iOS => ios.isNotEmpty,
    _ => false,
  };
}

/// The only host the Gmail client may talk to.
const gmailApiHost = 'gmail.googleapis.com';

/// Per-request ceiling (headers). The caller bounds the body read as well.
const gmailRequestTimeout = Duration(seconds: 30);

/// Adds the bearer header; nothing else. Refuses any host but [gmailApiHost],
/// any non-https URL, and never follows a redirect (a redirect would carry the
/// token to wherever it points). One short-lived instance per sync.
class GmailBearerClient extends http.BaseClient {
  GmailBearerClient(this._token, {http.Client? inner})
    : _inner = inner ?? http.Client();
  final String _token;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final u = request.url;
    if (u.scheme != 'https' || u.host != gmailApiHost) {
      throw http.ClientException('Blocked host: ${u.host}', u);
    }
    request.followRedirects = false;
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request).timeout(gmailRequestTimeout);
  }

  @override
  void close() => _inner.close();
}

const _signInFailed = 'Could not sign in to Google. Try again.';

/// Platform calls that must not hang a sync.
const _platformTimeout = Duration(seconds: 30);

/// Messages larger than this are not downloaded in full: their snippet stands
/// in for the body.
const maxGmailMessageBytes = 1024 * 1024;

class SystemGmailSource implements GmailSource {
  SystemGmailSource({
    this.ids = GmailClientIds.fromEnvironment,
    TargetPlatform? platform,
  }) : _platform = platform ?? defaultTargetPlatform;

  final GmailClientIds ids;
  final TargetPlatform _platform;

  // google_sign_in must be initialised exactly once per process.
  static Future<void>? _initialised;

  @override
  bool get configured => ids.supportedOn(_platform);

  Future<void> _init() => _initialised ??= GoogleSignIn.instance.initialize(
    clientId: _platform == TargetPlatform.iOS ? ids.ios : null,
    serverClientId: ids.server.isEmpty ? null : ids.server,
  );

  @override
  Future<String?> signIn() async {
    try {
      await _init();
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: const [gmailReadonlyScope],
      );
      final client = account.authorizationClient;
      // Consent is the interactive step; later syncs only ask silently.
      final granted =
          await client.authorizationForScopes(const [gmailReadonlyScope]) ??
          await client.authorizeScopes(const [gmailReadonlyScope]);
      // Dropped at once: nothing is kept from the sign-in but the email.
      await client.clearAuthorizationToken(accessToken: granted.accessToken);
      return account.email;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        await _quietSignOut();
        return null;
      }
      throw const GmailAuthException(_signInFailed);
    }
  }

  Future<void> _quietSignOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }

  /// A short-lived access token, silently, or [GmailAuthException].
  Future<(GoogleSignInAuthorizationClient, String)> _token() async {
    try {
      await _init().timeout(_platformTimeout);
      final attempt = GoogleSignIn.instance.attemptLightweightAuthentication();
      final account = attempt == null
          ? null
          : await attempt.timeout(_platformTimeout);
      if (account == null) throw const GmailAuthException(_signInFailed);
      final client = account.authorizationClient;
      final auth = await client
          .authorizationForScopes(const [gmailReadonlyScope])
          .timeout(_platformTimeout);
      // Null means Google would have to show UI: never from a sync.
      if (auth == null) throw const GmailAuthException(_signInFailed);
      return (client, auth.accessToken);
    } on GoogleSignInException {
      throw const GmailAuthException(_signInFailed);
    } on TimeoutException {
      throw const GmailAuthException(_signInFailed);
    }
  }

  /// Whole-read ceiling: per-request timeouts bound each call, this bounds the
  /// sum, so a sync (and `SyncService`) can never hang for good.
  static const _readCeiling = Duration(minutes: 4);

  @override
  Future<GmailFetch> recentThreads({
    required DateTime since,
    required int maxThreads,
  }) => _read(since, maxThreads).timeout(_readCeiling);

  Future<GmailFetch> _read(DateTime since, int maxThreads) async {
    final (auth, token) = await _token();
    final client = GmailBearerClient(token);
    try {
      return await readRecentThreads(
        gmail.GmailApi(client),
        since: since,
        maxThreads: maxThreads,
      );
    } on gmail.DetailedApiRequestError catch (e) {
      if (gmailNeedsSignIn(e)) {
        // A rejected token must not be handed out again.
        try {
          await auth.clearAuthorizationToken(accessToken: token);
        } catch (_) {}
        throw const GmailAuthException(_signInFailed);
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  @override
  Future<bool> signOut() async {
    try {
      await _init().timeout(_platformTimeout);
      // After a cold start the plugin only knows accounts it has seen in this
      // process, so ask for the signed-in one first; without it there is
      // nothing to revoke from here.
      final attempt = GoogleSignIn.instance.attemptLightweightAuthentication();
      final account = attempt == null
          ? null
          : await attempt.timeout(_platformTimeout);
      if (account != null) {
        await GoogleSignIn.instance.disconnect().timeout(_platformTimeout);
        return true;
      }
    } catch (_) {}
    try {
      await GoogleSignIn.instance.signOut().timeout(_platformTimeout);
    } catch (_) {}
    return false;
  }
}

/// True for the API errors that mean "the user must sign in again".
bool gmailNeedsSignIn(gmail.DetailedApiRequestError e) =>
    e.status == 401 ||
    (e.status == 403 &&
        e.errors.any(
          (x) =>
              x.reason == 'insufficientPermissions' ||
              x.reason == 'forbidden' ||
              x.reason == 'authError',
        ));

/// Reads the inbox through [api]: pages the listing up to [maxThreads], then
/// each thread's newest message. [GmailFetch.complete] needs the listing read
/// to its end and no thread skipped. A thread that fails to read (vanished,
/// timed out, odd shape, server error) is skipped; only a sign-in problem
/// escapes, because it fails every thread alike. Public for tests, which drive
/// it with a fake HTTP client.
Future<GmailFetch> readRecentThreads(
  gmail.GmailApi api, {
  required DateTime since,
  required int maxThreads,
}) async {
  final ids = <String>[];
  String? page;
  var exhausted = false;
  while (ids.length < maxThreads) {
    final r = await api.users.threads
        .list(
          'me',
          labelIds: const ['INBOX'],
          // Epoch seconds: exact, unlike newer_than:Nd.
          q: 'after:${since.millisecondsSinceEpoch ~/ 1000}',
          maxResults: maxThreads - ids.length,
          pageToken: page,
        )
        .timeout(_platformTimeout);
    for (final t in r.threads ?? const <gmail.Thread>[]) {
      if (t.id != null && ids.length < maxThreads) ids.add(t.id!);
    }
    page = r.nextPageToken;
    if (page == null || page.isEmpty) {
      exhausted = true;
      break;
    }
  }
  final out = <GmailThread>[];
  var skipped = false;
  // Small batches: a phone, not a crawler.
  for (var i = 0; i < ids.length; i += 8) {
    final batch = await Future.wait([
      for (final id in ids.skip(i).take(8)) _readOne(api, id),
    ]);
    for (final t in batch) {
      if (t == null) {
        skipped = true;
      } else {
        out.add(t);
      }
    }
  }
  return GmailFetch(out, complete: exhausted && !skipped);
}

Future<GmailThread?> _readOne(gmail.GmailApi api, String id) async {
  try {
    // Headers and labels only: no bodies, so a thread of huge messages costs
    // little.
    final meta = await api.users.threads
        .get(
          'me',
          id,
          format: 'metadata',
          metadataHeaders: const ['From', 'Subject'],
        )
        .timeout(_platformTimeout);
    final newest = newestMessage(meta.messages);
    if (newest?.id == null) return null;
    var m = newest!;
    if ((m.sizeEstimate ?? 0) <= maxGmailMessageBytes) {
      m = await api.users.messages
          .get('me', m.id!, format: 'full')
          .timeout(_platformTimeout);
    }
    return GmailThread(id, [
      gmailMessageFromApi(m),
    ], messageCount: meta.messages?.length);
  } on gmail.DetailedApiRequestError catch (e) {
    if (gmailNeedsSignIn(e)) rethrow;
    return null;
  } catch (_) {
    return null;
  }
}

// ---- API object -> our types (pure, bounded) -------------------------------

String _cut(String s, int max) => capText(s, max);

String _unquote(String s) {
  var a = 0, b = s.length;
  bool junk(int c) => c <= 0x20 || c == 0x22 || c == 0x27;
  while (a < b && junk(s.codeUnitAt(a))) {
    a++;
  }
  while (b > a && junk(s.codeUnitAt(b - 1))) {
    b--;
  }
  return s.substring(a, b);
}

/// A From header: `Ravi K <ravi@x.com>`, `<ravi@x.com>`, a bare address or a
/// bare name. Linear string scanning, no regex: the value is attacker
/// controlled and may be enormous. Results are capped.
Person? parseFromHeader(String? raw) {
  final s = raw?.trim() ?? '';
  if (s.isEmpty) return null;
  final lt = s.lastIndexOf('<');
  final gt = s.lastIndexOf('>');
  if (lt >= 0 && gt > lt && s.substring(gt + 1).trim().isEmpty) {
    final name = _unquote(s.substring(0, lt));
    final email = s.substring(lt + 1, gt).trim();
    return Person(
      name: name.isEmpty ? null : _cut(name, maxMailNameChars),
      email: email.isEmpty ? null : _cut(email, maxMailEmailChars),
    );
  }
  return s.contains('@')
      ? Person(email: _cut(s, maxMailEmailChars))
      : Person(name: _cut(s, maxMailNameChars));
}

/// Decodes the common HTML entities of a Gmail snippet (`&amp;`, `&#39;`,
/// `&#x1F600;`). Linear; unknown entities stay as they are.
String decodeHtmlEntities(String s) {
  if (!s.contains('&')) return s;
  return s.replaceAllMapped(
    RegExp(r'&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[a-zA-Z]{2,6});'),
    (m) {
      final e = m.group(1)!;
      if (e.startsWith('#')) {
        final hex = e.length > 1 && (e[1] == 'x' || e[1] == 'X');
        final code = int.tryParse(
          e.substring(hex ? 2 : 1),
          radix: hex ? 16 : 10,
        );
        if (code == null || code == 0 || code > 0x10FFFF) return m.group(0)!;
        if (code >= 0xD800 && code <= 0xDFFF) return m.group(0)!;
        return String.fromCharCode(code);
      }
      return switch (e) {
        'amp' => '&',
        'lt' => '<',
        'gt' => '>',
        'quot' => '"',
        'apos' => "'",
        'nbsp' => ' ',
        _ => m.group(0)!,
      };
    },
  );
}

String? _header(gmail.Message m, String name) {
  for (final h in m.payload?.headers ?? const <gmail.MessagePartHeader>[]) {
    if ((h.name ?? '').toLowerCase() == name) return h.value;
  }
  return null;
}

/// Most base64 characters decoded per part (about 12 KB of text).
const maxBodyBase64Chars = 16384; // a multiple of 4

/// MIME nesting and total parts looked at.
const maxMimeDepth = 6;
const maxMimeParts = 64;

/// Decodes at most [maxBodyBase64Chars] of a base64url [data]: the encoded
/// string is cut BEFORE decoding (on a 4-character boundary), so a 20 MB body
/// costs the same as a 12 KB one. Bad base64 gives null; bad UTF-8 is replaced.
String? decodeBodyData(String? data) {
  if (data == null || data.isEmpty) return null;
  final s = data.length > maxBodyBase64Chars
      ? data.substring(0, maxBodyBase64Chars)
      : data;
  try {
    return utf8.decode(
      base64Url.decode(base64Url.normalize(s)),
      allowMalformed: true,
    );
  } on FormatException {
    return null;
  }
}

/// First text/plain part, breadth bounded by [maxMimeParts] and depth by
/// [maxMimeDepth]. ponytail: assumes UTF-8 whatever the part's charset says,
/// and never converts HTML (the snippet stands in).
String? plainTextOf(gmail.MessagePart? root) {
  var budget = maxMimeParts;
  String? walk(gmail.MessagePart? part, int depth) {
    if (part == null || depth > maxMimeDepth || budget-- <= 0) return null;
    if (part.mimeType == 'text/plain') {
      final t = decodeBodyData(part.body?.data);
      if (t != null) return t;
    }
    for (final p in part.parts ?? const <gmail.MessagePart>[]) {
      final t = walk(p, depth + 1);
      if (t != null) return t;
    }
    return null;
  }

  return walk(root, 0);
}

/// The message with the latest `internalDate`.
gmail.Message? newestMessage(List<gmail.Message>? messages) {
  gmail.Message? best;
  var bestAt = -1;
  for (final m in messages ?? const <gmail.Message>[]) {
    final at = int.tryParse(m.internalDate ?? '') ?? 0;
    if (best == null || at > bestAt) {
      best = m;
      bestAt = at;
    }
  }
  return best;
}

/// Maps one API message; every text field is capped here.
GmailMessage gmailMessageFromApi(gmail.Message m) => GmailMessage(
  id: m.id ?? '',
  from: parseFromHeader(_header(m, 'from')),
  subject: _cut(_header(m, 'subject') ?? '', maxMailSubjectChars),
  date: DateTime.fromMillisecondsSinceEpoch(
    int.tryParse(m.internalDate ?? '') ?? 0,
  ),
  text: capText(
    plainTextOf(m.payload) ??
        decodeHtmlEntities(_cut(m.snippet ?? '', maxItemBodyChars)),
    maxItemBodyChars,
  ),
  labels: {...?m.labelIds},
);

/// Maps an API thread to its newest message only.
GmailThread gmailThreadFromApi(gmail.Thread t) {
  final newest = newestMessage(t.messages);
  return GmailThread(t.id ?? '', [
    if (newest != null && newest.id != null) gmailMessageFromApi(newest),
  ], messageCount: t.messages?.length);
}
