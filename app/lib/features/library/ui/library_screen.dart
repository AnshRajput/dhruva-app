/// Library: the connected folder (index status, Search files), your documents,
/// to-dos and saved answers. Matches the approved library comp. Every section
/// has a real empty state that ends in an action that works, so Library is
/// never a dead end; sections load with skeleton rows and name a retry on
/// failure.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/platform_chrome.dart';
import '../widgets/folder_block.dart';
import '../widgets/library_sections.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    return ChromeScaffold(
      appBar: AdaptiveAppBar(
        title: const Text('Library'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            key: const ValueKey('library-search'),
            tooltip: 'Search files',
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/library/search'),
          ),
        ],
      ),
      bodyBuilder: (context, inset) => ListView(
        padding: EdgeInsets.fromLTRB(
          tokens.spacing.base,
          inset.top + tokens.spacing.xs,
          tokens.spacing.base,
          inset.bottom + tokens.spacing.xl2,
        ),
        children: const [
          FolderBlock(),
          DocumentsSection(),
          TodosSection(),
          SavedSection(),
        ],
      ),
    );
  }
}
