/// "Open settings" for permission-denied states (microphone today; calendar,
/// notifications and files later). An app cannot re-grant a permission the user
/// denied, so the honest fix is a button that opens this app's page in the
/// system Settings.
///
/// * Android: a tiny method on the existing `dhruva/intents` channel
///   (`openAppSettings`, `MainActivity.kt`) launching
///   `ACTION_APPLICATION_DETAILS_SETTINGS` for this package.
/// * iOS: the `app-settings:` URL via the already-bundled `url_launcher`.
///
/// Never throws: a failure returns false so the caller can fall back to
/// words ("open Settings, then Apps").
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'intent_inbox.dart' show IntentInbox;

/// Opens this app's page in system Settings. True when the OS accepted it.
Future<bool> openAppSettings({
  MethodChannel? channel,
  TargetPlatform? platform,
  Future<bool> Function(Uri url)? launch,
}) async {
  final target = platform ?? defaultTargetPlatform;
  try {
    if (target == TargetPlatform.iOS) {
      return await (launch ?? launchUrl)(Uri.parse('app-settings:'));
    }
    final ok = await (channel ?? const MethodChannel(IntentInbox.channelName))
        .invokeMethod<bool>('openAppSettings');
    return ok ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

/// Injectable so widget tests never touch a platform channel.
final openAppSettingsProvider = Provider<Future<bool> Function()>(
  (ref) =>
      () => openAppSettings(),
);
