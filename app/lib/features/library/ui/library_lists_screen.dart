/// "See all" pages of the Library (`/library/documents`, `/library/saved`):
/// the full list, full-screen, with a back button.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/platform_chrome.dart';
import '../widgets/library_sections.dart';

class _ListScreen extends StatelessWidget {
  const _ListScreen({required this.title, required this.body});
  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    return ChromeScaffold(
      appBar: AdaptiveAppBar(title: Text(title)),
      bodyBuilder: (context, inset) => ListView(
        padding: EdgeInsets.fromLTRB(
          tokens.spacing.base,
          inset.top + tokens.spacing.xs,
          tokens.spacing.base,
          inset.bottom + tokens.spacing.xl2,
        ),
        children: [body],
      ),
    );
  }
}

class DocumentsScreen extends StatelessWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const _ListScreen(title: 'Documents', body: DocumentsSection(all: true));
}

class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const _ListScreen(title: 'Saved', body: SavedSection(all: true));
}
