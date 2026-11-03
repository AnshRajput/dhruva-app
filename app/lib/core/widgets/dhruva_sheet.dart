/// The one way to present a bottom sheet. Sixteen call sites each used
/// Flutter's defaults (or three different hand-set styles), so sheet timing
/// drifted. One helper pins it: 250 ms in, 160 ms out (exit faster than enter,
/// inside the 300 ms UI budget). The curve is Material's own
/// (`Easing.legacyDecelerate`, ease-out) and cannot be overridden in this SDK;
/// a future custom route replaces it here, in one place.
///
/// Reduced motion: the sheet keeps its fade but the durations collapse.
library;

import 'package:flutter/material.dart';

const _enter = Duration(milliseconds: 250);
const _exit = Duration(milliseconds: 160);

Future<T?> showDhruvaSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  bool isScrollControlled = false,
  bool showDragHandle = false,
  bool useSafeArea = false,
  bool isDismissible = true,
  bool enableDrag = true,
  BoxConstraints? constraints,
  ShapeBorder? shape,
  Clip? clipBehavior,
  Color? barrierColor,
  bool useRootNavigator = false,
}) {
  final reduce = MediaQuery.disableAnimationsOf(context);
  return showModalBottomSheet<T>(
    context: context,
    // `useSafeArea` leaves the bottom open, so every sheet clears the gesture
    // bar here, once. Under the keyboard the inset is already consumed.
    builder: (context) => SafeArea(top: false, child: builder(context)),
    backgroundColor: backgroundColor,
    isScrollControlled: isScrollControlled,
    showDragHandle: showDragHandle,
    useSafeArea: useSafeArea,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    constraints: constraints,
    shape: shape,
    clipBehavior: clipBehavior,
    barrierColor: barrierColor,
    useRootNavigator: useRootNavigator,
    sheetAnimationStyle: AnimationStyle(
      duration: reduce ? Duration.zero : _enter,
      reverseDuration: reduce ? Duration.zero : _exit,
    ),
  );
}
