/// Full-size "tap to view" for an attached image bubble (Loop 7). A modal
/// route + `InteractiveViewer` (pinch-to-zoom) is the whole feature — no
/// dedicated screen needed for a lightbox this simple.
///
/// Motion: the route fades in with a 0.96 -> 1 scale (180 ms in, 140 ms out,
/// ease-out; a plain fade under reduced motion) instead of a hard cut. At rest
/// (not zoomed) a swipe down dismisses it, the way every photo viewer does;
/// once zoomed the same drag pans the image instead.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/theme/design_tokens.dart';

Future<void> showImageLightbox(BuildContext context, Uint8List imageBytes) {
  // Designer BLOCKING: no raw Colors literals — scrim is the exact token for a
  // modal backdrop; the close icon reads from the color scheme so it stays
  // legible against the scrim in both themes.
  final colorScheme = Theme.of(context).colorScheme;
  final reduce = MediaQuery.disableAnimationsOf(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close image',
    barrierColor: colorScheme.scrim,
    transitionDuration: reduce
        ? Duration.zero
        : const Duration(milliseconds: 180),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: TokenMotionCurve.decelerate,
        reverseCurve: TokenMotionCurve.decelerate,
      );
      return FadeTransition(
        opacity: curved,
        child: reduce
            ? child
            : ScaleTransition(
                scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
                child: child,
              ),
      );
    },
    pageBuilder: (context, _, _) => _Lightbox(imageBytes: imageBytes),
  );
}

class _Lightbox extends StatefulWidget {
  const _Lightbox({required this.imageBytes});

  final Uint8List imageBytes;

  @override
  State<_Lightbox> createState() => _LightboxState();
}

class _LightboxState extends State<_Lightbox> {
  final _controller = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final zoomed = _controller.value.getMaxScaleOnAxis() > 1.01;
      if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: Dismissible(
              key: const ValueKey('image-lightbox'),
              direction: _zoomed
                  ? DismissDirection.none
                  : DismissDirection.down,
              onDismissed: (_) => Navigator.of(context).pop(),
              child: InteractiveViewer(
                transformationController: _controller,
                // At rest the vertical drag belongs to swipe-to-dismiss.
                panEnabled: _zoomed,
                child: Center(child: Image.memory(widget.imageBytes)),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            right: 8,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(Icons.close, color: colorScheme.onSurface),
              tooltip: 'Close',
            ),
          ),
        ],
      ),
    );
  }
}
