/// "Check for updates": tap forces a check, or downloads / restarts per phase.
/// Lives on the About page (version first, then this row). Moved from the old
/// Settings list; behaviour unchanged (`update-row` key kept).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/update/shorebird_update_banner.dart' show updIosReady;
import '../../../core/update/shorebird_update_service.dart';
import 'settings_widgets.dart';

class UpdateRow extends ConsumerWidget {
  const UpdateRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(shorebirdUpdateProvider);
    final n = ref.read(shorebirdUpdateProvider.notifier);
    void say(String m) =>
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    final (String sub, VoidCallback? tap) = switch (s.phase) {
      ShorebirdPhase.unavailable => (
        "Updates aren't available in this build",
        null,
      ),
      ShorebirdPhase.available => ('Update available', n.download),
      ShorebirdPhase.downloading => ('Downloading update…', null),
      ShorebirdPhase.readyToRestart =>
        s.reopenByHand
            ? (updIosReady, null)
            : ('Update ready. Tap to restart', n.restart),
      ShorebirdPhase.failed => ('Update failed. Tap to retry', n.download),
      ShorebirdPhase.idle => (
        s.patch == null ? 'Up to date' : 'Patch ${s.patch}',
        () async {
          final ok = await n.check(force: true);
          if (!context.mounted) return;
          if (!ok) {
            say("Couldn't check for updates.");
          } else if (ref.read(shorebirdUpdateProvider).phase ==
              ShorebirdPhase.idle) {
            say("You're up to date.");
          }
        },
      ),
    };
    return SettingsRow(
      key: const ValueKey('update-row'),
      icon: Icons.system_update_alt_rounded,
      title: 'Check for updates',
      subtitle: sub,
      onTap: tap,
    );
  }
}
