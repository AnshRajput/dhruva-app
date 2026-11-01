/// The one-tap row under the brief. Each chip opens the right place already
/// filled in: Summarize / Draft reply take the clipboard into Actions, Plan my
/// day and Ask my files open Ask with the matching connector pinned. When the
/// source is not connected the chip says so and goes to Connectors instead of
/// opening something that cannot work.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/connector_providers.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../data/connectors/connector.dart';

/// Max characters of clipboard text carried in the router URL (mirrors the
/// share-sheet bound in `IntentInbox`; Actions trims to the model context).
const maxClipboardChars = 16000;

const planMyDayPrompt =
    'Plan my day from my calendar: what to do first, where I have free time, '
    'and what I should prepare.';

class QuickActionsRow extends ConsumerWidget {
  const QuickActionsRow({super.key});

  Future<void> _clipboardAction(BuildContext context, String id) async {
    ClipboardData? data;
    try {
      data = await Clipboard.getData(Clipboard.kTextPlain);
    } on Object {
      data = null; // an unreadable clipboard reads as empty
    }
    var text = data?.text?.trim() ?? '';
    if (!context.mounted) return;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Clipboard is empty. Copy some text, or paste it in.'),
        ),
      );
      await context.push('/actions?id=$id');
      return;
    }
    if (text.length > maxClipboardChars) {
      text = text.substring(0, maxClipboardChars);
    }
    await context.push(
      '/actions?id=$id&text=${Uri.encodeQueryComponent(text)}',
    );
  }

  /// Opens Ask with [sources] pinned if that connector is on, otherwise tells
  /// the user what to connect and goes there.
  void _askWith(
    BuildContext context,
    WidgetRef ref, {
    required String connectorId,
    required String sources,
    required String needs,
    String? prompt,
  }) {
    final entries = ref.read(connectorListProvider).value ?? const [];
    final on = entries.any(
      (e) => e.connector.id == connectorId && e.status.isConnected,
    );
    if (!on) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$needs first. It stays on this phone.')),
      );
      unawaited(context.push('/settings/connectors'));
      return;
    }
    final p = prompt == null
        ? ''
        : 'prompt=${Uri.encodeQueryComponent(prompt)}&';
    unawaited(context.push('/chat/new?${p}sources=$sources'));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    final actions = <(String, IconData, String, VoidCallback)>[
      (
        'summarize',
        Icons.content_paste_rounded,
        'Summarize clipboard',
        () => _clipboardAction(context, 'summarize'),
      ),
      (
        'draft_reply',
        Icons.edit_outlined,
        'Draft reply',
        () => _clipboardAction(context, 'draft_reply'),
      ),
      (
        'plan',
        Icons.event_outlined,
        'Plan my day',
        () => _askWith(
          context,
          ref,
          connectorId: ConnectorIds.calendar,
          sources: 'calendar',
          needs: 'Connect your calendar',
          prompt: planMyDayPrompt,
        ),
      ),
      (
        'files',
        Icons.folder_outlined,
        'Ask my files',
        () => _askWith(
          context,
          ref,
          connectorId: ConnectorIds.folder,
          sources: 'folder',
          needs: 'Connect a folder',
        ),
      ),
    ];
    return SizedBox(
      height: 48,
      child: ListView(
        key: const ValueKey('today-quick-actions'),
        scrollDirection: Axis.horizontal,
        children: [
          for (final (id, icon, label, onTap) in actions) ...[
            PressableScale(
              onTap: onTap,
              semanticLabel: label,
              child: _Pill(
                icon: icon,
                label: label,
                keyValue: 'today-action-$id',
              ),
            ),
            SizedBox(width: tokens.spacing.sm),
          ],
          PressableScale(
            onTap: () => context.push('/actions'),
            semanticLabel: 'All actions',
            child: const _Pill(
              icon: Icons.arrow_forward_rounded,
              label: 'All actions',
              keyValue: 'today-action-all',
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.keyValue,
  });

  final IconData icon;
  final String label;
  final String keyValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return DecoratedBox(
      key: ValueKey(keyValue),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(tokens.radius.full),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: tokens.spacing.base),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            SizedBox(width: tokens.spacing.sm),
            Text(label, style: theme.textTheme.labelLarge),
          ],
        ),
      ),
    );
  }
}
