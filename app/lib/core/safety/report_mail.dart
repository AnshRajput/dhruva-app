/// `mailto:` builders for the developer contact, shared by the report sheet
/// (chat) and the Safety & reports screen (settings). Pure Dart; launching
/// is the caller's `url_launcher` call (always user-initiated).
library;

const developerEmail = 'rithiksingh92119211@gmail.com';

/// `mailto:` URI with percent-encoded (not `+`) spaces, which every mail
/// client decodes correctly — `Uri(queryParameters:)` would emit `+`.
Uri developerMailto({required String subject, String body = ''}) {
  final query = [
    'subject=${Uri.encodeComponent(subject)}',
    if (body.isNotEmpty) 'body=${Uri.encodeComponent(body)}',
  ].join('&');
  return Uri.parse('mailto:$developerEmail?$query');
}

Uri reportMailto({
  required String reason,
  String? note,
  String? model,
  required String appVersion,
  required String excerpt,
}) {
  final body = StringBuffer()
    ..writeln('Reason: $reason')
    ..writeln('Note: ${note == null || note.isEmpty ? '(none)' : note}')
    ..writeln('Model: ${model ?? 'unknown'}')
    ..writeln('App version: $appVersion')
    ..writeln()
    ..writeln('Reported reply:')
    ..write(excerpt);
  return developerMailto(
    subject: 'Dhruva AI content report',
    body: body.toString(),
  );
}
