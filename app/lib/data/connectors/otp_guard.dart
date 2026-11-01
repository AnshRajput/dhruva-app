/// Verification codes never reach the store. A notification whose title or
/// text carries verification wording (English or Hindi) AND a 4 to 8 digit code
/// is saved with its text replaced by [hiddenCodeBody]; the code is gone before
/// anything is written, so it cannot be searched, summarised or shown.
///
/// Deliberately conservative: it would rather hide an ordinary "code 2024"
/// notice than keep a real one-time password. Android 15 already redacts OTP
/// text for listeners on its own; this covers older versions and apps that
/// slip through.
library;

/// What is stored (and shown) instead of the text.
const hiddenCodeBody = 'Verification code (hidden)';

/// Item flag set on a redacted notification. Summaries skip such items.
const otpFlag = 'otp';

// Latin wording: otp, one-time / one time, passcode / pass code, verification
// (code), security code, login / sign-in / confirmation code.
final _wordingEn = RegExp(
  r'\botps?\b|one[\s-]?time|pass[\s-]?code|verif(?:y|ication|ying)|'
  r'(?:security|login|log-in|sign-in|confirmation|auth(?:entication)?)\s+code',
  caseSensitive: false,
);

// Hindi: ओटीपी (OTP) and कोड (code). Plain contains, no word boundaries: \b
// does not understand Devanagari.
final _wordingHi = RegExp('ओटीपी|कोड');

// 4 to 8 digits (ASCII or Devanagari), optionally split as 123-456 / 123 456.
// Not part of a longer digit run (an order id or a phone number).
const _digit = '[0-9०-९]';
final _code = RegExp(
  '(?<!$_digit)(?:$_digit{4,8}|$_digit{3}[- ]$_digit{3})(?!$_digit)',
);

/// True when [title] / [text] look like a verification code message.
bool looksLikeVerificationCode(String title, String text) {
  final all = '$title\n$text';
  final worded = _wordingEn.hasMatch(all) || _wordingHi.hasMatch(all);
  return worded && _code.hasMatch(all);
}
