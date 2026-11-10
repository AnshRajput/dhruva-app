/// Pure builder for the in-app "Report a bug / Request a feature" email draft.
/// No IO, no plugins: everything that ends up in the email is decided here, so
/// one test file pins exactly what can leave the phone (and only after the user
/// taps Send in their own mail app).
///
/// NEVER included, by construction (there is no field for them): chats,
/// documents, connector data, calendar, contacts, notification contents,
/// file-system paths, device identifiers.
library;

import 'package:flutter/foundation.dart';

import '../crash/crash_log.dart';
import '../identity/app_identity.dart';

enum FeedbackType {
  bug('Bug', 'Report a bug'),
  feature('Feature', 'Request a feature');

  const FeedbackType(this.label, this.title);

  /// Subject tag and body "Type:" line.
  final String label;

  /// Row / screen title.
  final String title;

  /// Prompt on the description field.
  String get descriptionPrompt => this == bug
      ? 'What happened? What did you expect?'
      : 'What would you like ${AppIdentity.shortName} to do?';
}

/// The one place the route string is built (Settings rows, crash banner).
String feedbackRoute(FeedbackType type, {bool fromCrash = false}) =>
    '/settings/feedback?type=${type.name}${fromCrash ? '&crash=1' : ''}';

const feedbackTitleMax = 120;
const feedbackMaxAttachments = 5;
const feedbackMaxAttachmentBytes = 20 * 1024 * 1024;

/// Newest crash records included when the crash log is ticked.
const feedbackCrashRecords = 5;

const feedbackCrashLogFileName = 'crash-log.txt';
const feedbackNeverIncluded = 'Your chats and files are never included.';

/// A picked screenshot / video. [name] is the bare file name (never a path
/// shown to the user or written into the email body); [path] is only handed
/// to the mail plugin as an attachment.
@immutable
class FeedbackAttachment {
  const FeedbackAttachment({
    required this.path,
    required this.name,
    required this.bytes,
  });

  final String path;
  final String name;
  final int bytes;

  static const _videoExt = {'mp4', 'mov', 'm4v', '3gp', 'webm', 'mkv'};

  bool get isVideo => _videoExt.contains(name.split('.').last.toLowerCase());
}

/// An installed model by name + size. Deliberately has no path field.
@immutable
class FeedbackModel {
  const FeedbackModel(this.name, this.bytes);
  final String name;
  final int bytes;
}

/// The device facts the user can opt in to share.
@immutable
class FeedbackDeviceInfo {
  const FeedbackDeviceInfo({
    required this.phoneModel,
    required this.os,
    required this.appVersion,
    required this.appBuild,
    this.models = const [],
    this.freeRamBytes,
    this.totalRamBytes,
    this.freeStorageBytes,
    this.totalStorageBytes,
  });

  final String phoneModel;
  final String os;
  final String appVersion;
  final String appBuild;
  final List<FeedbackModel> models;
  final int? freeRamBytes;
  final int? totalRamBytes;
  final int? freeStorageBytes;
  final int? totalStorageBytes;

  String toBlock() {
    final models = this.models.isEmpty
        ? 'none'
        : this.models
              .map((m) => '${m.name} (${formatFeedbackBytes(m.bytes)})')
              .join(', ');
    return [
      'Phone: $phoneModel',
      'OS: $os',
      'App: ${AppIdentity.shortName} $appVersion (build $appBuild)',
      'Installed models: $models',
      'Free RAM: ${_of(freeRamBytes, totalRamBytes)}',
      'Free storage: ${_of(freeStorageBytes, totalStorageBytes)}',
    ].join('\n');
  }

  static String _of(int? free, int? total) => free == null
      ? 'unknown'
      : total == null
      ? formatFeedbackBytes(free)
      : '${formatFeedbackBytes(free)} of ${formatFeedbackBytes(total)}';
}

String formatFeedbackBytes(int bytes) {
  const gb = 1024 * 1024 * 1024;
  const mb = 1024 * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  if (bytes >= mb) {
    return '${(bytes / mb).toStringAsFixed(bytes >= 10 * mb ? 0 : 1)} MB';
  }
  return '${(bytes / 1024).ceil()} KB';
}

/// What the user typed and ticked.
@immutable
class FeedbackDraft {
  const FeedbackDraft({
    required this.type,
    this.title = '',
    this.description = '',
    this.steps = '',
    this.attachments = const [],
    this.deviceInfo,
    this.crashRecords,
  });

  final FeedbackType type;
  final String title;
  final String description;

  /// Bug only; ignored for features.
  final String steps;
  final List<FeedbackAttachment> attachments;

  /// Null = "Include device info" is off.
  final FeedbackDeviceInfo? deviceInfo;

  /// Null = "Include recent crash log" is off. Records are the existing,
  /// already-scrubbed [CrashRecord]s.
  final List<CrashRecord>? crashRecords;
}

String cleanTitle(String raw) => raw.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Plain-word error for the title, or null when fine.
String? validateFeedbackTitle(String raw) {
  final t = cleanTitle(raw);
  if (t.isEmpty) return 'Add a short title.';
  if (t.length > feedbackTitleMax) {
    return 'Keep the title under $feedbackTitleMax characters.';
  }
  return null;
}

String? validateFeedbackDescription(String raw) =>
    raw.trim().isEmpty ? 'Tell us a little more.' : null;

const feedbackTooManyFiles =
    'You can add up to $feedbackMaxAttachments files. '
    'Remove one to add another.';

/// Plain-word error if adding [incoming] to [current] breaks a limit, else
/// null. Pure, so the limits are pinned by tests.
String? checkAttachmentLimits(
  List<FeedbackAttachment> current,
  List<FeedbackAttachment> incoming,
) {
  if (current.length + incoming.length > feedbackMaxAttachments) {
    return feedbackTooManyFiles;
  }
  final total = [...current, ...incoming].fold<int>(0, (s, a) => s + a.bytes);
  if (total > feedbackMaxAttachmentBytes) {
    return 'Files together must be under '
        '${feedbackMaxAttachmentBytes ~/ (1024 * 1024)} MB. '
        'Remove one or pick a smaller one.';
  }
  return null;
}

@immutable
class FeedbackReport {
  const FeedbackReport({
    required this.subject,
    required this.body,
    required this.mediaPaths,
    required this.crashLogText,
  });

  final String subject;
  final String body;
  final List<String> mediaPaths;

  /// Content of `crash-log.txt` when ticked, else null.
  final String? crashLogText;
}

FeedbackReport buildFeedbackReport(FeedbackDraft d, {required String version}) {
  final title = cleanTitle(d.title);
  final steps = d.steps.trim();
  final b = StringBuffer()
    ..writeln('Type: ${d.type.label}')
    ..writeln('Title: $title')
    ..writeln()
    ..writeln('Description:')
    ..writeln(d.description.trim());
  if (d.type == FeedbackType.bug && steps.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Steps to reproduce:')
      ..writeln(steps);
  }
  if (d.deviceInfo != null) {
    b
      ..writeln()
      ..writeln('Device info:')
      ..writeln(d.deviceInfo!.toBlock());
  }
  final crash = d.crashRecords;
  return FeedbackReport(
    subject: '[${AppIdentity.shortName} $version][${d.type.label}] $title',
    body: b.toString().trimRight(),
    mediaPaths: [for (final a in d.attachments) a.path],
    crashLogText: crash == null || crash.isEmpty
        ? null
        : formatCrashReport(crash.take(feedbackCrashRecords).toList()),
  );
}

/// One sentence saying exactly what the email will contain.
String feedbackPreview(FeedbackDraft d) {
  final parts = <String>[
    'your title and description',
    if (d.type == FeedbackType.bug && d.steps.trim().isNotEmpty) 'your steps',
    if (d.attachments.isNotEmpty)
      '${d.attachments.length} '
          '${d.attachments.length == 1 ? 'file' : 'files'}',
    if (d.deviceInfo != null)
      'phone model, OS, app version, installed model names and sizes, '
          'free RAM and storage',
    if (d.crashRecords != null && d.crashRecords!.isNotEmpty)
      'the recent crash log',
  ];
  return 'This will share: ${parts.join(', ')}.';
}
