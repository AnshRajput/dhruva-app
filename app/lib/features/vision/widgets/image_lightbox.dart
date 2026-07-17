/// Full-size "tap to view" for an attached image bubble (Loop 7). A modal
/// dialog + `InteractiveViewer` (pinch-to-zoom) is the whole feature — no
/// dedicated route/screen needed for a lightbox this simple.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

Future<void> showImageLightbox(BuildContext context, Uint8List imageBytes) {
  // Designer BLOCKING: no raw Colors literals — scrim is the exact token for a
  // modal backdrop; the close icon reads from the color scheme so it stays
  // legible against the scrim in both themes.
  final colorScheme = Theme.of(context).colorScheme;
  return showDialog<void>(
    context: context,
    barrierColor: colorScheme.scrim,
    builder: (context) => Dialog(
      insetPadding: EdgeInsets.zero,
      backgroundColor: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              child: Center(child: Image.memory(imageBytes)),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(Icons.close, color: colorScheme.onSurface),
              tooltip: 'Close',
            ),
          ),
        ],
      ),
    ),
  );
}
