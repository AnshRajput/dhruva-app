/// Personas gallery (Loop 5, formerly the Characters tab; now `/personas`, reached from Ask): a grid of built-in +
/// user characters, a "+ Create" affordance, and a file → parse → preview →
/// save import entry point for community character cards.
library;

import 'dart:io' show FileSystemException;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/failures/app_failure.dart';
import '../../../core/theme/brand_star.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/failure_view.dart';
import '../../../core/widgets/platform_chrome.dart' show isCupertinoChrome;
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
        title: const Text('Personas'),
        actions: [
          // iOS chrome has no floating action button: Create is a bar action.
          if (isCupertinoChrome(context))
            IconButton(
              tooltip: 'Create',
              icon: const Icon(Icons.add),
              onPressed: () => context.push('/characters/new'),
            ),
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
        AsyncError(:final error) => ErrorStateView(
          error: error,
          onRetry: () => ref.invalidate(charactersControllerProvider),
        ),
        _ => const Center(child: DhruvaLoader()),
      },
      // D8: ONE Create CTA. The empty gallery already carries its own
      // "Create a persona" button, so the FAB only appears once there is
      // something in the grid.
      floatingActionButton: switch (state) {
        AsyncData(:final value)
            when value.characters.isNotEmpty && !isCupertinoChrome(context) =>
          FloatingActionButton.extended(
            onPressed: () => context.push('/characters/new'),
            icon: const Icon(Icons.add),
            label: const Text('Create'),
          ),
        _ => null,
      },
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
    } on FileSystemException catch (e) {
      // QA MED: `readAsString()`/`readAsBytes()` on a picked file can throw
      // this directly (e.g. non-UTF-8 bytes on the JSON path) — a real I/O
      // failure, not a card-content problem, but the user still deserves
      // the same "typed failure, snackbar, never crash" treatment every
      // malformed-card case above already gets, not an uncaught crash.
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not read that file: ${e.message}')),
      );
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
              // Designer BLOCKING #3 (Loop 5 fix pass): a generic Material
              // icon here broke iconography.motif's "the brand's recurring
              // star, not a generic icon" rule that chat's own empty states
              // already follow — swapped for the shared `DhruvaStar` (core/
              // theme/brand_star.dart's cross-feature-safe copy).
              DhruvaStar(size: 72, color: theme.colorScheme.primary),
              SizedBox(height: tokens.spacing.lg),
              Text(
                'No personas yet',
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
                child: const Text('Create a persona'),
              ),
            ],
          ),
        ),
      );
    }

    // "Yours" first, then the starter pack under its own heading: built-in is a
    // section, not a pill on every card.
    final mine = [
      for (final c in characters)
        if (!c.isBuiltIn) c,
    ];
    final builtIn = [
      for (final c in characters)
        if (c.isBuiltIn) c,
    ];
    Widget row(CharacterInfo c) => Padding(
      padding: EdgeInsets.only(bottom: tokens.spacing.sm),
      child: CharacterTile(
        character: c,
        onTap: () => context.push('/characters/${c.id}'),
      ),
    );
    Widget heading(String text) => Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.spacing.xs,
        tokens.spacing.md,
        tokens.spacing.xs,
        tokens.spacing.sm,
      ),
      child: Text(text, style: theme.textTheme.titleMedium),
    );

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(charactersControllerProvider.notifier).refresh(),
      child: ListView(
        padding: EdgeInsets.all(tokens.spacing.md),
        children: [
          if (mine.isNotEmpty) ...[
            heading('Yours'),
            for (final c in mine) row(c),
          ],
          if (builtIn.isNotEmpty) ...[
            heading('Built-in'),
            for (final c in builtIn) row(c),
          ],
        ],
      ),
    );
  }
}
