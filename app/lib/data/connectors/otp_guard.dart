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

// Apps whose notifications are very often just a code: SMS apps, the dialer /
// caller-id app, and authenticator apps. Only these get the bare-code rule.
const _codeSenders = {
  'com.google.android.apps.messaging',
  'com.android.messaging',
  'com.samsung.android.messaging',
  'com.android.mms',
  'com.oneplus.mms',
  'com.truecaller',
  'com.google.android.apps.authenticator2',
  'com.azure.authenticator',
  'com.microsoft.msa.authenticator',
};

/// Letter runs of two or more characters: the "words" left once the code is
/// taken out ("is your code" is 3; the "G" of "G-731942" is none).
final _wordsLeft = RegExp(r'\p{L}{2,}', unicode: true);

/// True when [title] / [text] look like a verification code message. [pkg] is
/// the posting app: from an app that commonly sends codes (see `_codeSenders`),
/// a body that is mostly a code token ("G-731942", "482913 is your code") is
/// hidden even without verification wording.
bool looksLikeVerificationCode(String title, String text, {String? pkg}) {
  final all = '$title\n$text';
  final worded = _wordingEn.hasMatch(all) || _wordingHi.hasMatch(all);
  if (worded && _code.hasMatch(all)) return true;
  if (pkg == null || !_codeSenders.contains(pkg)) return false;
  // The text is the message; the title is only the sender, unless the text is
  // empty and the code sits in the title.
  final body = text.trim().isEmpty ? title : text;
  return _code.hasMatch(body) &&
      _wordsLeft.allMatches(body.replaceAll(_code, ' ')).length <= 3;
}

// ---- mail ------------------------------------------------------------------
//
// Mail has no sending app to key the bare-code rule on, and its text is long, so
// the rule is: a code WORD near a code TOKEN. Both searches are bounded windows,
// never a scan of the whole body per match, so hostile text cannot make it slow.

// Words that name a code. "verify" alone is weaker (see below).
final _mailCodeWord = RegExp(
  r'\b(?:otps?|one[\s-]?time|pass[\s-]?code|code|pin)\b|'
  'ओटीपी|कोड',
  caseSensitive: false,
);
final _mailVerifyWord = RegExp(
  r'\bverif(?:y|ication|ying)\b',
  caseSensitive: false,
);

// Case-sensitive on purpose: a code is digits, or capitals with digits.
//  - 4 to 8 digits, or 3-3 split;
//  - "G-731942" style: 1-3 capitals, dash, 4-8 digits;
//  - 5 to 8 capitals/digits with at least one of each ("AB12CD").
final _mailToken = RegExp(
  r'(?<![A-Za-z0-9])(?:[0-9०-९]{4,8}|[0-9०-९]{3}[- ][0-9०-९]{3}|[A-Z]{1,3}-[0-9]{4,8}|'
  r'(?=[A-Z0-9]{5,8}(?![A-Za-z0-9]))(?=[A-Z0-9]*[0-9])(?=[A-Z0-9]*[A-Z])'
  r'[A-Z0-9]{5,8})(?![A-Za-z0-9])',
);

final _plainYear = RegExp(r'^(?:19|20)[0-9]{2}$');

const _window = 60;
const _maxWordMatches = 200;

bool _tokenNear(String s, Match word, {required bool allowYear}) {
  final from = word.start - _window < 0 ? 0 : word.start - _window;
  final to = word.end + _window > s.length ? s.length : word.end + _window;
  for (final t in _mailToken.allMatches(s.substring(from, to))) {
    if (allowYear || !_plainYear.hasMatch(t.group(0)!)) return true;
  }
  return false;
}

/// True when a mail's [subject] / [text] carries a verification code: a code
/// word (otp, code, passcode, pin, one-time ...) within 60 characters of a code
/// token, or a "verify" word near one that is not a plain year ("verify by
/// 2026" is not a code). Conservative: it hides a real mail that merely
/// mentions a code. A code with no wording around it is not caught.
bool looksLikeMailCode(String subject, String text) {
  final s = '$subject\n$text';
  var n = 0;
  for (final w in _mailCodeWord.allMatches(s)) {
    if (++n > _maxWordMatches) break;
    if (_tokenNear(s, w, allowYear: true)) return true;
  }
  n = 0;
  for (final w in _mailVerifyWord.allMatches(s)) {
    if (++n > _maxWordMatches) break;
    if (_tokenNear(s, w, allowYear: false)) return true;
  }
  return false;
}
