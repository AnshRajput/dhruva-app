/// One character gallery grid cell: avatar, name, a one-line persona
/// preview, and a subtle "Built-in" marker for starter-pack characters.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../data/characters/character_repository.dart';
import 'character_avatar.dart';

class CharacterTile extends StatelessWidget {
  final CharacterInfo character;
  final VoidCallback onTap;

  const CharacterTile({
    super.key,
    required this.character,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;

    return InkWell(
      borderRadius: BorderRadius.circular(tokens.radius.md),
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(tokens.spacing.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(tokens.radius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CharacterAvatar(
                  avatarEmoji: character.avatarEmoji,
                  avatarPath: character.avatarPath,
                  size: 40,
                ),
                const Spacer(),
                if (character.isBuiltIn)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: tokens.spacing.xs,
                      vertical: 2,
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
              ],
            ),
            SizedBox(height: tokens.spacing.sm),
            Text(
              character.name,
              style: theme.textTheme.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: tokens.spacing.xs),
            Expanded(
              child: Text(
                character.personaSystemPrompt,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
