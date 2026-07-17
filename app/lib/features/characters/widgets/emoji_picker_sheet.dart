/// A curated emoji grid for picking a character's avatar — deliberately not
/// a full emoji-keyboard dependency (ladder rung 5: an already-installed
/// package would be the next reach, but there isn't one in this repo, and a
/// fixed curated set of persona-relevant emoji is simpler and on-brand for a
/// "characters" picker than exhaustive Unicode coverage).
library;

import 'package:flutter/material.dart';

import '../../../core/theme/dhruva_theme_extension.dart';

const _curatedEmoji = [
  '🙂',
  '😀',
  '😎',
  '🤓',
  '🧐',
  '🤔',
  '😌',
  '🥳',
  '🧑‍💻',
  '🧑‍🍳',
  '🧑‍🏫',
  '🧑‍⚕️',
  '🧑‍🎨',
  '🧑‍🚀',
  '🕵️',
  '🧙',
  '🦸',
  '🧝',
  '🐱',
  '🐶',
  '🦊',
  '🐼',
  '🦁',
  '🐧',
  '🐉',
  '🦉',
  '🐢',
  '🌟',
  '⭐',
  '💪',
  '📚',
  '📖',
  '🍳',
  '🗺️',
  '⚖️',
  '🌿',
  '🎈',
  '🧠',
  '🎭',
  '🎨',
];

/// Returns the picked emoji, or null if dismissed.
Future<String?> showEmojiPickerSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _EmojiPickerSheet(),
  );
}

class _EmojiPickerSheet extends StatelessWidget {
  const _EmojiPickerSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Choose an avatar', style: theme.textTheme.titleMedium),
            SizedBox(height: tokens.spacing.sm),
            SizedBox(
              height: 280,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                ),
                itemCount: _curatedEmoji.length,
                itemBuilder: (context, i) => InkWell(
                  borderRadius: BorderRadius.circular(tokens.radius.sm),
                  onTap: () => Navigator.of(context).pop(_curatedEmoji[i]),
                  child: Center(
                    child: Text(
                      _curatedEmoji[i],
                      style: const TextStyle(fontSize: 26),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
