/// The one human line under a persona's name in the gallery. The stored system
/// prompt is instructions to the model ("You are Chef, a practical..."), never
/// something to print on a card. Built-in personas get a hand-written line;
/// anything else (yours, imported) gets its first sentence with the "You are"
/// preamble removed.
library;

import '../../../data/characters/character_repository.dart';

/// Hand-written lines for the starter pack, by persona name.
/// `persona_blurb_test.dart` fails if a starter persona is missing here.
const builtInBlurbs = <String, String>{
  'Writing Coach': 'Makes your writing clearer, in your own voice',
  "Explain Like I'm New": "Plain answers for topics you're new to",
  'Hindi-English Translator': 'Translates both ways, in natural words',
  'Concise Assistant': 'Short answers, no padding',
  'Coach': 'A kind but honest accountability partner',
  'Study Buddy': 'Helps you understand, not just get answers',
  'Storyteller': 'Builds stories with you, scene by scene',
  'Hinglish Dost': 'A casual friend who talks in Hinglish',
  'Code Reviewer': 'Finds bugs and tidies your code',
  'Calm Companion': 'A steady presence when you need to talk',
  'Chef': 'Practical cooking help from what you have',
  'Travel Planner': 'Plans trips around what you like',
  'Debate Partner': 'Tests your ideas, fairly',
  "Kids' Tutor": 'Gentle, age-appropriate help for children',
};

const _maxLen = 64;

String personaBlurb(CharacterInfo c) {
  if (c.isBuiltIn) {
    final known = builtInBlurbs[c.name];
    if (known != null) return known;
  }
  return blurbFromPrompt(c.personaSystemPrompt);
}

/// First sentence of [prompt] without a leading "You are (a|an) ...", capped.
String blurbFromPrompt(String prompt) {
  var s = prompt.trim().split(RegExp(r'[.\n!?](\s|$)')).first.trim();
  final m = RegExp(
    r'^you are\s+(an?\s+|the\s+)?',
    caseSensitive: false,
  ).firstMatch(s);
  if (m != null) {
    final hadArticle = m.group(1) != null;
    s = s.substring(m.end);
    // "You are Chef, a practical cook" -> "A practical cook" (a name, then a
    // description); "You are a concise assistant" -> "Concise assistant".
    final comma = s.indexOf(',');
    if (!hadArticle && comma > 0 && comma < 24) {
      s = s.substring(comma + 1).trim();
    }
  }
  if (s.isEmpty) return '';
  s = '${s[0].toUpperCase()}${s.substring(1)}';
  if (s.length <= _maxLen) return s;
  final cut = s.lastIndexOf(' ', _maxLen - 1);
  return '${s.substring(0, cut > 20 ? cut : _maxLen - 1)}…';
}
