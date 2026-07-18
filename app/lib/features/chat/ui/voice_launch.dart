/// Launches hands-free voice from the chat feature (WS5 "obvious entry
/// point"). Shared by the chat thread's app-bar mic AND the Chats-home "Talk"
/// action so the closure + controller-lifecycle logic lives in exactly one
/// place — both callers are in `features/chat`, so this never breaches
/// ADR-002 (only `core/router` may bridge chat<->voice, which it already does
/// via the `/voice/handsfree` route's `extra` closure).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/chat_controller.dart';
import '../state/message_info_x.dart';

/// Opens hands-free voice against the chat controller for [args], keeping that
/// controller alive for the whole session and building the "say this, get the
/// reply" closure `HandsFreeScreen` needs.
///
/// The Chats home has no live `ChatController` the way `ChatThreadScreen` does
/// (which `ref.watch`es its provider), so [ref.listenManual] pins the
/// `autoDispose` family for the session and is closed once the voice screen
/// pops — otherwise the new-chat controller could be torn down between turns.
/// `ChatController.sendMessage` loads the model itself, so [args] only needs a
/// picked `initialModelId`, not a pre-loaded controller.
Future<void> openHandsFreeVoice(
  BuildContext context,
  WidgetRef ref,
  ChatRouteArgs args,
) async {
  final provider = chatControllerProvider(args);
  final keepAlive = ref.listenManual(provider, (_, _) {});
  final controller = ref.read(provider.notifier);

  Future<String?> onUserUtterance(String text) async {
    await controller.sendMessage(text);
    final last = ref.read(provider).value?.visibleMessages.lastOrNull;
    if (last == null ||
        last.role != MessageRole.assistant ||
        last.status == MessageStatus.error ||
        last.content.trim().isEmpty) {
      return null;
    }
    return last.content;
  }

  await context.push('/voice/handsfree', extra: onUserUtterance);
  keepAlive.close();
}
