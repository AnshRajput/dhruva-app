/// One persona in the gallery: a compact row with the avatar, the name and ONE
/// human line about it (not the raw system prompt). Built-in vs yours is the
/// gallery's section, never a pill repeated on every card.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../data/characters/character_repository.dart';
import 'character_avatar.dart';
import 'persona_blurb.dart';

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
    final blurb = personaBlurb(character);

    return PressableScale(
      onTap: onTap,
      semanticLabel: blurb.isEmpty
          ? character.name
          : '${character.name}. $blurb',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.md,
          vertical: tokens.spacing.sm,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(tokens.radius.md),
        ),
        child: Row(
          children: [
            CharacterAvatar(
              avatarEmoji: character.avatarEmoji,
              avatarPath: character.avatarPath,
              size: 40,
            ),
            SizedBox(width: tokens.spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    character.name,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (blurb.isNotEmpty)
                    Text(
                      blurb,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
