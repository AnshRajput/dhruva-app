/// Characters gallery (Loop 5) — the `/characters` tab: a grid of built-in +
/// user characters, a "+ Create" affordance, and a file → parse → preview →
/// save import entry point for community character cards.
library;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failures/app_failure.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../data/characters/character_card.dart';
import '../../../data/characters/character_repository.dart';
import '../state/characters_controller.dart';
import '../widgets/character_tile.dart';
import '../widgets/import_preview_dialog.dart';

class CharactersGalleryScreen extends ConsumerWidget {
  const CharactersGalleryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(charactersControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Characters'),
        actions: [
          PopupMenuButton<bool>(
            tooltip: 'Import a character card',
            icon: const Icon(Icons.file_upload_outlined),
            onSelected: (isJson) => _import(context, ref, isJson),
            itemBuilder: (context) => const [
              PopupMenuItem(value: true, child: Text('Import JSON card')),
              PopupMenuItem(value: false, child: Text('Import PNG card')),
            ],
          ),
        ],
      ),
      body: switch (state) {
        AsyncData(:final value) => _GalleryBody(characters: value.characters),
        AsyncError() => const Center(child: Text('Could not load characters.')),
        _ => const Center(child: CircularProgressIndicator()),
      },
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/characters/new'),
        icon: const Icon(Icons.add),
        label: const Text('Create'),
      ),
    );
  }

  Future<void> _import(BuildContext context, WidgetRef ref, bool json) async {
    final typeGroup = XTypeGroup(
      label: json ? 'JSON card' : 'PNG card',
      extensions: [json ? 'json' : 'png'],
    );
    final picked = await openFile(acceptedTypeGroups: [typeGroup]);
    if (picked == null) return;

    try {
      final CharacterCardV2 card;
      if (json) {
        card = CharacterCardV2.parse(await picked.readAsString());
      } else {
        card = CharacterCardV2.fromJson(
          extractCardFromPng(await picked.readAsBytes()),
        );
      }
      final fields = cardToCharacterFields(card);
      if (!context.mounted) return;
      final confirmed = await showImportPreviewDialog(context, fields);
      if (confirmed != true) return;
      await ref
          .read(charactersControllerProvider.notifier)
          .saveImported(fields);
    } on ValidationFailure catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _GalleryBody extends ConsumerWidget {
  final List<CharacterInfo> characters;
  const _GalleryBody({required this.characters});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;

    if (characters.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.theater_comedy_outlined,
                size: 72,
                color: theme.colorScheme.primary,
              ),
              SizedBox(height: tokens.spacing.lg),
              Text(
                'No characters yet',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: tokens.spacing.sm),
              Text(
                'Create a persona to chat with, or import a character card.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: tokens.spacing.lg),
              FilledButton(
                onPressed: () => context.push('/characters/new'),
                child: const Text('Create a character'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(charactersControllerProvider.notifier).refresh(),
      child: GridView.builder(
        padding: EdgeInsets.all(tokens.spacing.md),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.85,
        ),
        itemCount: characters.length,
        itemBuilder: (context, i) {
          final character = characters[i];
          return CharacterTile(
            character: character,
            onTap: () => context.push('/characters/${character.id}'),
          );
        },
      ),
    );
  }
}
