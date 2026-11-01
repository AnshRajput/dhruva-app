/// Bridges Android system entry points into the router: text selected in any
/// app ("Ask Dhruva AI" in the selection menu), text shared from the share
/// sheet, and launcher shortcuts. Native side is `MainActivity.kt` on the
/// `dhruva/intents` channel: `getInitialIntent` at cold start, and
/// `onIntent` pushed on later `onNewIntent`s. Payload:
/// `{text?, route?, replaceable?}`; `replaceable` is true when the text came
/// from the selection menu of an editable field, so the result can be handed
/// back (see `process_text.dart`).
///
/// ponytail: iOS share extension is out of scope here; add a Share Extension
/// target that writes to an app group and feed it through this same inbox.
library;

import 'package:flutter/services.dart';

class IntentInbox {
  static const channelName = 'dhruva/intents';
  static const _maxSharedChars = 16000;

  /// Navigates to a router location (injected so tests need no router).
  final void Function(String location) navigate;

  /// Told, for every payload, whether the launch can return a result to the
  /// source app. Null in tests that don't care.
  final void Function(bool replaceable)? onReplaceable;
  final MethodChannel _channel;

  IntentInbox({
    required this.navigate,
    this.onReplaceable,
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel(channelName);

  /// Only a payload that carries text and an explicit `replaceable: true`.
  static bool isReplaceable(Map<Object?, Object?>? payload) =>
      payload != null &&
      payload['replaceable'] == true &&
      ((payload['text'] as String?)?.trim().isNotEmpty ?? false);

  /// Maps a native payload to a router location, or null if it carries
  /// nothing actionable. Shared text wins over a shortcut route.
  static String? locationFor(Map<Object?, Object?>? payload) {
    if (payload == null) return null;
    var text = (payload['text'] as String?)?.trim() ?? '';
    // Bound the router URL for huge shares. Above the workflow sheet's own
    // 12k limit on purpose, so the sheet still trims and says so.
    if (text.length > _maxSharedChars) {
      text = text.substring(0, _maxSharedChars);
    }
    if (text.isNotEmpty) {
      return '/actions?text=${Uri.encodeQueryComponent(text)}';
    }
    return switch (payload['route']) {
      'new_chat' => '/chat/new',
      'workflows' => '/actions',
      // Launcher shortcuts for the two new front doors.
      'today' => '/today',
      'ask' => '/ask',
      // Widget "Talk" button: a fresh chat that opens hands-free on arrival.
      'talk' => '/chat/new?talk=1',
      _ => null,
    };
  }

  void handle(Map<Object?, Object?>? payload) {
    final location = locationFor(payload);
    if (location == null) return;
    onReplaceable?.call(isReplaceable(payload));
    navigate(location);
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
