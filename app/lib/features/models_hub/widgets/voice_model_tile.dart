/// One row in the models hub "Voice" tab (Loop 6, D4): a
/// [VoiceCatalogEntry] + its live [VoiceModelState].
library;

import 'package:flutter/material.dart';

import '../../../voice/voice_model_catalog.dart';
import '../state/voice_models_controller.dart';

class VoiceModelTile extends StatelessWidget {
  final VoiceModelState state;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  const VoiceModelTile({
    super.key,
    required this.state,
    required this.onDownload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = state.entry;
    return ListTile(
      leading: Icon(_roleIcon(entry.role)),
      title: Text(entry.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${entry.description} · ${_formatBytes(entry.downloadSizeBytes)}',
          ),
          if (state.status == VoiceModelStatus.downloading)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(value: state.progress),
            ),
          if (state.status == VoiceModelStatus.failed &&
              state.errorMessage != null)
            Text(
              state.errorMessage!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
        ],
      ),
      isThreeLine:
          state.status == VoiceModelStatus.downloading ||
          (state.status == VoiceModelStatus.failed &&
              state.errorMessage != null),
      trailing: _trailing(context),
    );
  }

  Widget _trailing(BuildContext context) {
    switch (state.status) {
      case VoiceModelStatus.installed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle,
              color: Theme.of(context).colorScheme.primary,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: onDelete,
            ),
          ],
        );
      case VoiceModelStatus.downloading:
      case VoiceModelStatus.installing:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case VoiceModelStatus.notInstalled:
        return IconButton(
          icon: const Icon(Icons.download_outlined),
          tooltip: 'Download',
          onPressed: onDownload,
        );
      case VoiceModelStatus.failed:
        return IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Retry',
          onPressed: onDownload,
        );
    }
  }

  IconData _roleIcon(VoiceModelRole role) => switch (role) {
    VoiceModelRole.asr => Icons.mic_outlined,
    VoiceModelRole.tts => Icons.record_voice_over_outlined,
    VoiceModelRole.vad => Icons.graphic_eq,
  };
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
  return '$bytes B';
}
