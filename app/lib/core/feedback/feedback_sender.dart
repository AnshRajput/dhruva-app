/// Hands a [FeedbackReport] to the user's OWN mail app (a draft they review and
/// send themselves), or, when no mail app / account exists, to the system share
/// sheet. The app makes no network call and has no server: it never sends
/// anything, so callers must never say "sent".
///
/// The platform bits sit behind [FeedbackTransport] so the fallback rule is
/// unit-tested with a fake; [SystemFeedbackTransport] is thin glue.
library;

import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../safety/report_mail.dart';
import 'feedback_report.dart';

/// No mail app, no account, or the composer could not open.
final class EmailUnavailable implements Exception {
  const EmailUnavailable([this.reason = '']);
  final String reason;
  @override
  String toString() => 'EmailUnavailable: $reason';
}

abstract interface class FeedbackTransport {
  /// Writes [text] to a temp file called [fileName] and returns its path.
  Future<String> stageText(String fileName, String text);

  /// Opens the mail composer. Throws [EmailUnavailable] if it cannot.
  Future<void> composeEmail({
    required String to,
    required String subject,
    required String body,
    required List<String> attachmentPaths,
  });

  Future<void> shareFallback({
    required String text,
    required String subject,
    required List<String> filePaths,
  });
}

enum FeedbackHandoff { emailDraft, shareSheet }

Future<List<String>> _files(
  FeedbackReport report,
  FeedbackTransport transport,
) async => [
  ...report.mediaPaths,
  if (report.crashLogText != null)
    await transport.stageText(feedbackCrashLogFileName, report.crashLogText!),
];

/// The system share sheet with the full body (address first) and the same
/// files. Always available: Android cannot say whether a mail account is set
/// up (a signed-out Gmail "succeeds" and shows a welcome tour), so the form
/// always offers this next to the email draft.
Future<FeedbackHandoff> shareFeedback(
  FeedbackReport report,
  FeedbackTransport transport,
) async {
  await transport.shareFallback(
    text: 'Please send to $developerEmail\n\n${report.body}',
    subject: report.subject,
    filePaths: await _files(report, transport),
  );
  return FeedbackHandoff.shareSheet;
}

/// Email draft first; share sheet when the plugin reports no mail app.
Future<FeedbackHandoff> sendFeedback(
  FeedbackReport report,
  FeedbackTransport transport,
) async {
  try {
    await transport.composeEmail(
      to: developerEmail,
      subject: report.subject,
      body: report.body,
      attachmentPaths: await _files(report, transport),
    );
    return FeedbackHandoff.emailDraft;
  } on EmailUnavailable {
    return shareFeedback(report, transport);
  }
}

final class SystemFeedbackTransport implements FeedbackTransport {
  @override
  Future<String> stageText(String fileName, String text) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}${Platform.pathSeparator}$fileName');
    await f.writeAsString(text, flush: true);
    return f.path;
  }

  @override
  Future<void> composeEmail({
    required String to,
    required String subject,
    required String body,
    required List<String> attachmentPaths,
  }) async {
    try {
      await FlutterEmailSender.send(
        feedbackEmail(
          to: to,
          subject: subject,
          body: body,
          attachmentPaths: attachmentPaths,
        ),
      );
    } on PlatformException catch (e) {
      throw EmailUnavailable(e.code);
    }
  }

  @override
  Future<void> shareFallback({
    required String text,
    required String subject,
    required List<String> filePaths,
  }) => SharePlus.instance
      .share(
        feedbackShareParams(text: text, subject: subject, filePaths: filePaths),
      )
      .then((_) {});
}

/// share_plus 13.2.1 THROWS `ArgumentError('files provided, but cannot be
/// empty')` for `files: []` (share_plus.dart:90-91); a text-only share must
/// pass `null`.
ShareParams feedbackShareParams({
  required String text,
  required String subject,
  required List<String> filePaths,
}) => ShareParams(
  text: text,
  subject: subject,
  files: filePaths.isEmpty ? null : [for (final p in filePaths) XFile(p)],
);

/// Same rule for the mail plugin: no attachments means `null`, not `[]`.
Email feedbackEmail({
  required String to,
  required String subject,
  required String body,
  required List<String> attachmentPaths,
}) => Email(
  recipients: [to],
  subject: subject,
  body: body,
  attachmentPaths: attachmentPaths.isEmpty ? null : attachmentPaths,
);

final feedbackTransportProvider = Provider<FeedbackTransport>(
  (ref) => SystemFeedbackTransport(),
);
