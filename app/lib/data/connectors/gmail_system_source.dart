/// Production [GmailSource]: `google_sign_in` 7.x for the account and the
/// silent `gmail.readonly` authorization, `googleapis` Gmail v1 for the reads.
///
/// Network: Google's sign-in and https://gmail.googleapis.com only. No token is
/// stored by this app; google_sign_in keeps its own credentials in the OS
/// (Credential Manager on Android, Keychain on iOS) and each sync asks for a
/// short-lived access token silently, holds it in a local variable for the
/// duration of the sync and drops it.
///
/// Needs OAuth client ids from the build (`--dart-define`):
///   GMAIL_SERVER_CLIENT_ID  the Web client id (Android requires it)
///   GMAIL_IOS_CLIENT_ID     the iOS client id (iOS requires it)
/// With the id for the platform empty, [configured] is false and the connector
/// card never appears.
///
/// Platform glue: needs a real Google sign-in to exercise end to end. The
/// mapping from API objects ([gmailThreadFromApi]) is pure and unit tested.
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

/// Adds the bearer header; nothing else. One short-lived instance per sync.
class _BearerClient extends http.BaseClient {
  _BearerClient(this._token);
  final String _token;
  final _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

const _signInFailed = 'Could not sign in to Google. Try again.';

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
      await _init();
      final account = await GoogleSignIn.instance
          .attemptLightweightAuthentication();
      if (account == null) throw const GmailAuthException(_signInFailed);
      final client = account.authorizationClient;
      final auth = await client.authorizationForScopes(const [
        gmailReadonlyScope,
      ]);
      // Null means Google would have to show UI: never from a sync.
      if (auth == null) throw const GmailAuthException(_signInFailed);
      return (client, auth.accessToken);
    } on GoogleSignInException {
      throw const GmailAuthException(_signInFailed);
    }
  }

  @override
  Future<List<GmailThread>> recentThreads({
    required DateTime since,
    required int maxThreads,
  }) async {
    final (auth, token) = await _token();
    final client = _BearerClient(token);
    try {
      final threads = gmail.GmailApi(client).users.threads;
      final listed = await threads.list(
        'me',
        labelIds: const ['INBOX'],
        // Epoch seconds: exact, unlike newer_than:Nd.
        q: 'after:${since.millisecondsSinceEpoch ~/ 1000}',
        maxResults: maxThreads,
      );
      final ids = [
        for (final t in listed.threads ?? const <gmail.Thread>[]) ?t.id,
      ].take(maxThreads).toList();
      final out = <GmailThread>[];
      // Small batches: a phone, not a crawler.
      for (var i = 0; i < ids.length; i += 8) {
        final batch = await Future.wait([
          for (final id in ids.skip(i).take(8)) _get(threads, id),
        ]);
        for (final t in batch) {
          if (t != null) out.add(gmailThreadFromApi(t));
        }
      }
      return out;
    } on gmail.DetailedApiRequestError catch (e) {
      if (_needsSignIn(e)) {
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

  /// One thread; null when it vanished between the list and the read.
  Future<gmail.Thread?> _get(
    gmail.UsersThreadsResource threads,
    String id,
  ) async {
    try {
      return await threads.get('me', id, format: 'full');
    } on gmail.DetailedApiRequestError catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  static bool _needsSignIn(gmail.DetailedApiRequestError e) =>
      e.status == 401 ||
      (e.status == 403 &&
          e.errors.any(
            (x) =>
                x.reason == 'insufficientPermissions' ||
                x.reason == 'forbidden' ||
                x.reason == 'authError',
          ));

  @override
  Future<void> signOut() async {
    await _init();
    try {
      // Revokes the grant at Google as well as signing out.
      await GoogleSignIn.instance.disconnect();
    } catch (_) {
      await GoogleSignIn.instance.signOut();
    }
  }
}

// ---- API object -> our types (pure) ----------------------------------------

/// A From header: `Ravi K <ravi@x.com>`, `<ravi@x.com>`, a bare address or a
/// bare name.
Person? parseFromHeader(String? raw) {
  final s = raw?.trim() ?? '';
  if (s.isEmpty) return null;
  final m = RegExp(r'^(.*?)\s*<([^<>]+)>\s*$').firstMatch(s);
  if (m == null) {
    return s.contains('@') ? Person(email: s) : Person(name: s);
  }
  final name = m.group(1)!.replaceAll(RegExp(r'''^["'\s]+|["'\s]+$'''), '');
  return Person(name: name.isEmpty ? null : name, email: m.group(2)!.trim());
}

String? _header(gmail.Message m, String name) {
  for (final h in m.payload?.headers ?? const <gmail.MessagePartHeader>[]) {
    if ((h.name ?? '').toLowerCase() == name) return h.value;
  }
  return null;
}

/// First text/plain part, depth first. ponytail: assumes UTF-8 whatever the
/// part's charset says, and never converts HTML (the snippet stands in).
String? _plainText(gmail.MessagePart? part) {
  if (part == null) return null;
  final data = part.body?.data;
  if (part.mimeType == 'text/plain' && data != null) {
    return utf8.decode(part.body!.dataAsBytes, allowMalformed: true);
  }
  for (final p in part.parts ?? const <gmail.MessagePart>[]) {
    final t = _plainText(p);
    if (t != null) return t;
  }
  return null;
}

/// Maps an API thread. The body is cut to the item cap here, so a huge message
/// is never held whole.
GmailThread gmailThreadFromApi(gmail.Thread t) => GmailThread(t.id ?? '', [
  for (final m in t.messages ?? const <gmail.Message>[])
    if (m.id != null)
      GmailMessage(
        id: m.id!,
        from: parseFromHeader(_header(m, 'from')),
        subject: _header(m, 'subject') ?? '',
        date: DateTime.fromMillisecondsSinceEpoch(
          int.tryParse(m.internalDate ?? '') ?? 0,
        ),
        text: capText(
          _plainText(m.payload) ?? m.snippet ?? '',
          maxItemBodyChars,
        ),
        labels: {...?m.labelIds},
      ),
]);
