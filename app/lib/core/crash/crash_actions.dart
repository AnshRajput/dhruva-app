import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../safety/report_mail.dart';
import 'crash_log.dart';

const crashSubject = 'Dhruva AI crash report';

/// Opens the system share sheet. The user picks the destination.
Future<void> shareCrashReport(List<CrashRecord> records) =>
    SharePlus.instance.share(
      ShareParams(text: formatCrashReport(records), subject: crashSubject),
    );

/// Opens the mail app with the report prefilled. mailto URLs are length
/// limited, so only the newest record is included, truncated.
Future<void> emailCrashReport(List<CrashRecord> records) {
  var body = formatCrashReport(records.take(1).toList());
  if (body.length > 1500) body = '${body.substring(0, 1500)}…[truncated]';
  return launchUrl(developerMailto(subject: crashSubject, body: body));
}
