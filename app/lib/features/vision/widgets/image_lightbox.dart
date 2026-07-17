/// Full-size "tap to view" for an attached image bubble (Loop 7). A modal
/// dialog + `InteractiveViewer` (pinch-to-zoom) is the whole feature — no
/// dedicated route/screen needed for a lightbox this simple.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

Future<void> showImageLightbox(BuildContext context, Uint8List imageBytes) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
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
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: 'Close',
            ),
          ),
        ],
      ),
    ),
  );
}
