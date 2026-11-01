/// "Hide content in app switcher" (Settings > Privacy), native side.
///
/// - Android: `FLAG_SECURE` on the activity window. Side effect the OS
///   imposes: screenshots and screen recording of the app are blocked too.
/// - iOS: a cover view over the window while the app is inactive/backgrounded
///   (`SceneDelegate`), so the app-switcher snapshot shows the cover.
///
/// Dart only forwards the on/off value over a MethodChannel. Any failure (no
/// native side in tests/desktop) is swallowed: a privacy nicety must never
/// crash the app.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class ScreenPrivacy {
  Future<void> setHidden(bool hidden);
}

final class ChannelScreenPrivacy implements ScreenPrivacy {
  const ChannelScreenPrivacy();

  static const channelName = 'app.dhruva/privacy';
  static const _channel = MethodChannel(channelName);

  @override
  Future<void> setHidden(bool hidden) async {
    try {
      await _channel.invokeMethod<void>('setHideInSwitcher', hidden);
    } on MissingPluginException {
      // No native handler (tests, desktop).
    } on PlatformException {
      // Best effort.
    }
  }
}

final screenPrivacyProvider = Provider<ScreenPrivacy>(
  (ref) => const ChannelScreenPrivacy(),
);
