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
      if (_sexual.hasMatch(sentence) && _mentionsMinor(sentence)) return true;
    }
    return false;
  }

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
    r'development|orientation|maturation)|sex ed\b',
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

  static final _sexual = RegExp(
    r'\b(?:sexual|sexually|sex scene|sex act|have sex|having sex|'
    r'sex with|sex tape|nude|nudes|naked|nudity|erotic|erotica|porn|'
    r'porno|pornographic|nsfw|fuck|fucking|orgasm|intercourse|masturbat\w*|'
    r'blowjob|handjob|genitals?|penis|vagina|breasts|topless|seduce|'
    r'seduction|molest\w*|rape|fetish|lewd|horny|cumshot|xxx)\b',
  );
}
