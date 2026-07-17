/// A character's avatar: a picked image (`avatarPath`) if set, else the
/// emoji (`avatarEmoji`), else a fallback glyph — one circular chip reused
/// by the gallery tile, detail screen, form, and chat AppBar-adjacent spots.
library;

import 'dart:io';

import 'package:flutter/material.dart';

class CharacterAvatar extends StatelessWidget {
  final String? avatarEmoji;
  final String? avatarPath;
  final double size;

  const CharacterAvatar({
    super.key,
    this.avatarEmoji,
    this.avatarPath,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = avatarPath;
    // ponytail: a sync existsSync() per build is a single cheap stat call
    // on a small local file — fine at this app's scale (a few dozen
    // characters, not a scrolling list of thousands); revisit with a
    // FutureBuilder/cache if that ever stops being true.
    final hasImage = path != null && File(path).existsSync();
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: theme.colorScheme.secondaryContainer,
        alignment: Alignment.center,
        child: hasImage
            ? Image.file(
                File(path),
                width: size,
                height: size,
                fit: BoxFit.cover,
              )
            : Text(avatarEmoji ?? '⭐', style: TextStyle(fontSize: size * 0.5)),
      ),
    );
  }
}
