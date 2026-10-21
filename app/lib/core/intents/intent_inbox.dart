/// Bridges Android system entry points into the router: text selected in any
/// app ("Ask Dhruva AI" in the selection menu), text shared from the share
/// sheet, and launcher shortcuts. Native side is `MainActivity.kt` on the
/// `dhruva/intents` channel: `getInitialIntent` at cold start, and
/// `onIntent` pushed on later `onNewIntent`s. Payload: `{text?, route?}`.
///
/// ponytail: iOS share extension is out of scope here; add a Share Extension
/// target that writes to an app group and feed it through this same inbox.
library;

import 'package:flutter/services.dart';

class IntentInbox {
  static const channelName = 'dhruva/intents';

  /// Navigates to a router location (injected so tests need no router).
  final void Function(String location) navigate;
  final MethodChannel _channel;

  IntentInbox({required this.navigate, MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// Maps a native payload to a router location, or null if it carries
  /// nothing actionable. Shared text wins over a shortcut route.
  static String? locationFor(Map<Object?, Object?>? payload) {
    if (payload == null) return null;
    final text = (payload['text'] as String?)?.trim() ?? '';
    if (text.isNotEmpty) {
      return '/workflows?text=${Uri.encodeQueryComponent(text)}';
    }
    return switch (payload['route']) {
      'new_chat' => '/chat/new',
      'workflows' => '/workflows',
      _ => null,
    };
  }

  void handle(Map<Object?, Object?>? payload) {
    final location = locationFor(payload);
    if (location != null) navigate(location);
  }

  /// Handles the launch intent, then listens for later ones. Safe on
  /// platforms without the native channel (iOS, tests).
  Future<void> start() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onIntent') {
        handle(call.arguments as Map<Object?, Object?>?);
      }
    });
    try {
      handle(
        await _channel.invokeMethod<Map<Object?, Object?>>('getInitialIntent'),
      );
    } on MissingPluginException {
      // No native side on this platform.
    }
  }
}
