/// Import preview (gallery screen's file → parse → preview → save flow):
/// shows exactly what a parsed community card will create as a character
/// before anything is persisted. Operates on `ImportedCharacterFields`
/// (`data/characters/character_card.dart`'s pure card→fields mapping) —
/// nothing here touches the repository.
library;

import 'package:flutter/material.dart';

import '../../../data/characters/character_card.dart';

/// Returns true if the user confirmed the import, false/null otherwise.
Future<bool?> showImportPreviewDialog(
  BuildContext context,
  ImportedCharacterFields fields,
) {
  return showDialog<bool>(
    context: context,
    builder: (context) => _ImportPreviewDialog(fields: fields),
  );
}

class _ImportPreviewDialog extends StatelessWidget {
  final ImportedCharacterFields fields;
  const _ImportPreviewDialog({required this.fields});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          if (fields.avatarEmoji != null) ...[
            Text(fields.avatarEmoji!, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
          ],
          Expanded(child: Text(fields.name, overflow: TextOverflow.ellipsis)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              fields.personaSystemPrompt,
              style: theme.textTheme.bodyMedium,
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
            ),
            if ((fields.greeting ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Greeting',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                fields.greeting!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (fields.exampleDialogues.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '${fields.exampleDialogues.length} example dialogue'
                '${fields.exampleDialogues.length == 1 ? '' : 's'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Import'),
        ),
      ],
    );
  }
}
