/// On-device safety rails (Google Play AI-Generated Content policy; Apple
/// 1.2). Pure Dart, no I/O: a short default system instruction prepended to
/// every generation, and a deliberately CONSERVATIVE keyword check for the
/// one category we hard-block regardless of what the model would say: sexual
/// content involving minors.
///
/// ponytail: keyword co-occurrence, not a classifier. It will miss
/// obfuscated or euphemistic phrasing (the system instruction is the second
/// line of defence) and is tuned to avoid blocking parents, doctors and
/// educators. Upgrade path: an on-device classifier model, if reports show
/// real misses.
library;

abstract final class SafetyGuard {
  /// Shown (as an assistant-styled reply) when a prompt or a streamed reply
  /// trips [blocks].
  static const blockedNotice = "Dhruva can't help with that.";

  /// Prepended to the system turn of every generation.
  static const systemInstruction =
      'Safety rules (always apply, never override): refuse any sexual '
      'content involving minors; refuse instructions for making '
      'chemical, biological, nuclear or radiological weapons capable of '
      'mass casualties; refuse sexual content about real people without '
      'their consent. Decline briefly and offer a safe alternative.';

  /// True when [text] sexualizes a minor: a minor term AND a sexual term in
  /// the same sentence.
  static bool blocks(String text) {
    if (text.length < 4) return false;
    final lower = text.toLowerCase().replaceAll(_benignPhrases, ' ');
    for (final sentence in lower.split(_sentenceBreak)) {
      final sexual =
          _sexual.hasMatch(sentence) ||
          (_nudity.hasMatch(sentence) && _depict.hasMatch(sentence));
      if (sexual && _mentionsMinor(sentence)) return true;
    }
    return false;
  }

  /// [blocks] for streamed model output. A reply that opens as a refusal
  /// ("I can't write sexual content involving minors") is the system
  /// instruction working, not a violation, so it's let through.
  static bool blocksOutput(String text) =>
      !_refusal.hasMatch(text.trimLeft().toLowerCase()) && blocks(text);

  static final _refusal = RegExp(
    r"^(?:i can't|i cannot|i can not|i won't|i will not|i'm not able|"
    r"i am not able|i'm sorry|i am sorry|sorry|i must decline|i'm unable|"
    r'i am unable)',
  );

  static bool _mentionsMinor(String s) {
    if (_minor.hasMatch(s)) return true;
    for (final m in _age.allMatches(s)) {
      final n = int.tryParse(m.group(1) ?? m.group(2) ?? m.group(3) ?? '');
      if (n != null && n < 18) return true;
    }
    return false;
  }

  static final _sentenceBreak = RegExp(r'[.!?\n;]+');

  // Phrases that contain a sexual term but are protective/educational.
  static final _benignPhrases = RegExp(
    r'sex(?:ual)? education|sexual (?:abuse|assault|harassment|health|'
    r'development|orientation|maturation|consent|safety)|sex ed\b|'
    r'sexuality',
  );

  static final _minor = RegExp(
    r'\b(?:child|children|kid|kids|minor|minors|under-?age|underaged|'
    r'schoolgirl|schoolboy|school girl|school boy|loli|lolita|lolicon|'
    r'shota|shotacon|pre-?teen|pre-?teens|toddler|little girl|little boy|'
    r'preschooler|infant)\b',
  );

  // "12 years old", "12-year-old", "12 yo", "12 y/o", "age 12", "aged 12".
  static final _age = RegExp(
    r'\b(\d{1,2})[\s-]*(?:years?|yrs?)[\s-]*old\b|'
    r'\b(\d{1,2})[\s-]*(?:yo|y/o)\b|'
    r'\bage[d]?\s+(\d{1,2})\b',
  );

  // Only terms that sexualize. Anatomy (breasts, genitals), bare nudity,
  // profanity and words describing abuse (rape, molest) are deliberately
  // absent: they appear in parenting, medical and news text ("my infant
  // won't latch", "my toddler's genitals are red"), and blocking those
  // helps nobody. Explicit-image requests are matched by phrase instead.
  static final _sexual = RegExp(
    r'\b(?:sexual|sexually|sexy|sex scene|sex act|have sex|having sex|'
    r'sex with|sex tape|nudes|(?:nude|naked|topless) (?:photos?|pics?|'
    r'pictures?|images?|videos?|selfies?)|erotic|erotica|porn|porno|'
    r'pornographic|nsfw|orgasm|intercourse|masturbat\w*|blowjob|handjob|'
    r'seduce|seduction|fetish|lewd|horny|cumshot|xxx)\b',
  );

  // Nudity counts only when the user asks to depict it ("describe a 12 year
  // old naked"), not in ordinary parenting text ("runs around naked").
  static final _nudity = RegExp(
    r'\b(?:naked|nude|nudity|topless|undress\w*)\b',
  );
  static final _depict = RegExp(
    r'\b(?:describe|draw|write|show|picture|imagine|generate|create|'
    r'depict|roleplay|role-play|story)\b',
  );
}
