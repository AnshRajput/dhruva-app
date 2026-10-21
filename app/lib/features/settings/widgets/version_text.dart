import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/update/shorebird_update_service.dart';
import '../app_info.dart';

/// "Version X (build Y) · patch N"; long-press copies "X+Y · patch N".
/// Shared by Settings and About so the two never drift.
class VersionText extends ConsumerWidget {
  const VersionText({super.key, this.style, this.textAlign});

  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patch =
        ref.watch(shorebirdUpdateProvider.select((s) => s.patch)) ?? 0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () async {
        await Clipboard.setData(ClipboardData(text: versionCopyText(patch)));
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Version copied.')));
      },
      child: Text(versionLine(patch), style: style, textAlign: textAlign),
    );
  }
}
