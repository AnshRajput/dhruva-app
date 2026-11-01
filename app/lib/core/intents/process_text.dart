/// "Replace selected text" for the Android text-selection menu (PROCESS_TEXT).
///
/// When "Ask Dhruva AI" is picked on an EDITABLE field, the native side
/// (`MainActivity.kt`, `ProcessTextActivity`) flags the launch as replaceable.
/// [IntentInbox] records that in [processTextSessionProvider]; the chat thread
/// then shows a "Replace selected text" button under the latest reply, which
/// calls [ProcessTextBridge.returnResult]. Native validates again and answers
/// the calling app with `setResult(RESULT_OK, ...EXTRA_PROCESS_TEXT)`, then
/// closes this screen.
///
/// The model's reply is only ever sent back on that explicit tap; nothing is
/// replaced automatically.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'intent_inbox.dart' show IntentInbox;

/// Longest result handed back to the calling app (characters). The native
/// side enforces the same cap (`MainActivity.MAX_RESULT_CHARS`).
const processTextMaxResultChars = 100000;

/// Why a result could not be sent back.
enum ProcessTextFailure { notReplaceable, empty, tooLong }

class ProcessTextBridge {
  final MethodChannel _channel;
  ProcessTextBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(IntentInbox.channelName);

  /// The text that would be sent for [reply], or null when it must not be:
  /// blank. Over-long text is rejected rather than truncated (a cut-off
  /// replacement would silently damage the user's text).
  static ProcessTextFailure? validate(String reply) {
    final text = reply.trim();
    if (text.isEmpty) return ProcessTextFailure.empty;
    if (text.length > processTextMaxResultChars) {
      return ProcessTextFailure.tooLong;
    }
    return null;
  }

  /// Sends [reply] back to the source app and finishes this screen. Returns
  /// null on success (the screen is closing) or the reason it was refused.
  Future<ProcessTextFailure?> returnResult(String reply) async {
    final problem = validate(reply);
    if (problem != null) return problem;
    try {
      await _channel.invokeMethod<bool>('setProcessTextResult', reply.trim());
      return null;
    } on PlatformException catch (e) {
      return switch (e.code) {
        'too_long' => ProcessTextFailure.tooLong,
        'empty' => ProcessTextFailure.empty,
        _ => ProcessTextFailure.notReplaceable,
      };
    } on MissingPluginException {
      return ProcessTextFailure.notReplaceable;
    }
  }
}

final processTextBridgeProvider = Provider<ProcessTextBridge>(
  (ref) => ProcessTextBridge(),
);

/// True while this launch can hand a result back to the app whose text field
/// opened the selection menu.
class ProcessTextSession extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool replaceable) => state = replaceable;
}

final processTextSessionProvider = NotifierProvider<ProcessTextSession, bool>(
  ProcessTextSession.new,
);

/// Plain-language message for a refused replacement.
String processTextFailureMessage(ProcessTextFailure failure) =>
    switch (failure) {
      ProcessTextFailure.notReplaceable =>
        "Couldn't send the text back to that app. Use Copy instead.",
      ProcessTextFailure.empty => 'There is no text to send back.',
      ProcessTextFailure.tooLong =>
        'This reply is too long to send back. Use Copy instead.',
    };
