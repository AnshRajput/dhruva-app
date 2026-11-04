/// A route that carries text to send (`/chat/new?prompt=...&asys=...`) is only
/// honoured when the app itself built the link. Spec section 8: no external
/// deep link may exist, and none may be able to auto-send. Defence in depth
/// behind the platform settings (no VIEW intent filter on Android;
/// `FlutterDeepLinkingEnabled` off on iOS, whose Info.plist still registers a
/// URL scheme for Google sign-in).
///
/// In-app code builds such a link with [trustedRouteKey]; the router then drops
/// `prompt`, `asys`, `pkg` and `app` from any link that does not carry the same
/// per-process key. The key is random per launch, so a web page or another app
/// cannot guess it.
library;

import 'dart:math';

/// Query parameter that carries the key.
const routeKeyParam = 'k';

final String trustedRouteKey = _newKey();

String _newKey() {
  final r = Random.secure();
  return List.generate(
    16,
    (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// True when [uri] was built by this process.
bool isTrustedRoute(Uri uri) =>
    uri.queryParameters[routeKeyParam] == trustedRouteKey;

/// Query parameter [name] of [uri], but only on a link this process built:
/// for any other link it is null, as if it were not there.
String? trustedParam(Uri uri, String name) =>
    isTrustedRoute(uri) ? uri.queryParameters[name] : null;
