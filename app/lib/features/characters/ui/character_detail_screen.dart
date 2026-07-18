/// Character detail (Loop 5): full persona view + the actions that make a
/// character useful — "Chat with {name}" (starts a NEW persona-bound
/// conversation, chat-spec.md-adjacent gate G1: the persona must actually
/// reach the engine, wired via `ChatController._buildFromCharacter`), Edit
/// (user characters only), Duplicate (built-ins only — see
/// `CharactersController.duplicate`'s doc), Export (card JSON + PNG),
/// Delete (user characters only, confirmed).
library;

import 'dart:async' show unawaited;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/di/providers.dart';
import '../../../core/theme/brand_star.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/failure_view.dart';
import '../../../data/characters/character_repository.dart';
import '../state/characters_controller.dart';
import '../widgets/character_avatar.dart';

class CharacterDetailScreen extends ConsumerWidget {
  final int characterId;
  const CharacterDetailScreen({super.key, required this.characterId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncCharacter = ref.watch(characterByIdProvider(characterId));
    return asyncCharacter.when(
      data: (character) {
        if (character == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Character')),
            body: const EmptyStateView(
              message: 'Character not found.',
              icon: Icons.person_off_outlined,
            ),
          );
        }
        return _DetailBody(character: character);
      },
      loading: () => const Scaffold(body: Center(child: DhruvaLoader())),
      error: (error, stack) => Scaffold(
        appBar: AppBar(title: const Text('Character')),
        body: ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(characterByIdProvider(characterId)),
        ),
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  final CharacterInfo character;
  const _DetailBody({required this.character});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;

    return Scaffold(
      appBar: AppBar(
        title: Text(character.name),
        actions: [
          IconButton(
            tooltip: 'Export',
            icon: const Icon(Icons.ios_share),
            onPressed: () => _showExportSheet(context, ref),
          ),
          if (!character.isBuiltIn)
            PopupMenuButton<_Action>(
              onSelected: (action) => _handle(context, ref, action),
              itemBuilder: (context) => const [
                PopupMenuItem(value: _Action.edit, child: Text('Edit')),
                PopupMenuItem(value: _Action.delete, child: Text('Delete')),
              ],
            )
          else
            IconButton(
              tooltip: 'Duplicate to edit',
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: () => _duplicate(context, ref),
            ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(tokens.spacing.md),
        children: [
          Center(
            child: Column(
              children: [
                CharacterAvatar(
                  avatarEmoji: character.avatarEmoji,
                  avatarPath: character.avatarPath,
                  size: 88,
                ),
                SizedBox(height: tokens.spacing.sm),
                Text(character.name, style: theme.textTheme.headlineSmall),
                if (character.isBuiltIn)
                  Padding(
                    padding: EdgeInsets.only(top: tokens.spacing.xs),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: tokens.spacing.sm,
                        vertical: tokens.spacing.xs / 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(tokens.radius.full),
                      ),
                      child: Text(
                        'Built-in',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: tokens.spacing.lg),
          FilledButton.icon(
            onPressed: () => _chatWith(context),
            icon: const Icon(Icons.chat_bubble_outline),
            label: Text('Chat with ${character.name}'),
          ),
          SizedBox(height: tokens.spacing.lg),
          _Section(title: 'Persona', body: character.personaSystemPrompt),
          if ((character.greeting ?? '').isNotEmpty)
            _Section(
              title: 'Greeting',
              body: character.greeting!,
              italic: true,
            ),
          if (character.exampleDialogues.isNotEmpty)
            _Section(
              title: 'Example dialogues',
              body: character.exampleDialogues.join('\n\n'),
            ),
          if (character.samplingParams != null)
            _Section(
              title: 'Sampling defaults',
              body:
                  'Temperature ${character.samplingParams!.temperature}, '
                  'Top-P ${character.samplingParams!.topP}, '
                  'Top-K ${character.samplingParams!.topK}',
            ),
        ],
      ),
    );
  }

  void _chatWith(BuildContext context) {
    // See app_router.dart's `/chat/:id` builder: a `characterId` query
    // param (not `extra`) keeps this feature from importing `ChatRouteArgs`
    // out of `features/chat` (ADR-002 cross-feature-import ban).
    unawaited(context.push('/chat/new?characterId=${character.id}'));
  }

  Future<void> _duplicate(BuildContext context, WidgetRef ref) async {
    final newId = await ref
        .read(charactersControllerProvider.notifier)
        .duplicate(character);
    if (newId != null && context.mounted) {
      unawaited(context.push('/characters/$newId/edit'));
    }
  }

  Future<void> _handle(
    BuildContext context,
    WidgetRef ref,
    _Action action,
  ) async {
    switch (action) {
      case _Action.edit:
        unawaited(context.push('/characters/${character.id}/edit'));
      case _Action.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete character?'),
            content: Text(
              '"${character.name}" and its persona will be permanently '
              "deleted. This doesn't affect any past conversations.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          await ref
              .read(charactersControllerProvider.notifier)
              .delete(character.id);
          if (context.mounted) context.pop();
        }
    }
  }

  Future<void> _showExportSheet(BuildContext context, WidgetRef ref) async {
    final format = await showModalBottomSheet<_ExportFormat>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Export as JSON card'),
              onTap: () => Navigator.pop(context, _ExportFormat.json),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Export as PNG card'),
              onTap: () => Navigator.pop(context, _ExportFormat.png),
            ),
          ],
        ),
      ),
    );
    if (format == null || !context.mounted) return;
    final repo = ref.read(characterRepositoryProvider);
    if (format == _ExportFormat.json) {
      final json = await repo.exportCardJson(character.id);
      await SharePlus.instance.share(
        ShareParams(text: json, subject: '${character.name} character card'),
      );
    } else {
      final bytes = await repo.exportCardPng(character.id);
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/${character.name}_card.png');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: '${character.name} character card',
        ),
      );
    }
  }
}

enum _Action { edit, delete }

enum _ExportFormat { json, png }

class _Section extends StatelessWidget {
  final String title;
  final String body;
  final bool italic;
  const _Section({
    required this.title,
    required this.body,
    this.italic = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          SizedBox(height: tokens.spacing.xs),
          Text(
            body,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ],
      ),
    );
  }
}
