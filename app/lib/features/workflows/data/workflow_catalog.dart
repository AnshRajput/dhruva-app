/// The Workflows catalog: short, single-purpose text verbs that small
/// on-device models do well (summarize, translate, rewrite, extract), as
/// opposed to open-ended chat they do poorly. Each is a prompt template with
/// an `{input}` slot and at most one option set. Rendering is a pure function
/// ([renderWorkflowPrompt]) so it is trivially testable; the screen hands the
/// result to `/chat/new?prompt=`, which auto-sends it.
library;

import 'package:flutter/material.dart';

/// One choice set (e.g. target language) substituted into `{option}`.
class WorkflowOption {
  final String label;
  final List<String> choices;
  const WorkflowOption(this.label, this.choices);

  String get defaultChoice => choices.first;
}

class Workflow {
  final String id;
  final IconData icon;
  final String title;
  final String description;

  /// Contains `{input}` and, when [option] is set, `{option}`.
  final String template;
  final WorkflowOption? option;

  /// Input field hint, e.g. "Paste the report here".
  final String inputHint;

  const Workflow({
    required this.id,
    required this.icon,
    required this.title,
    required this.description,
    required this.template,
    this.option,
    this.inputHint = 'Paste or type your text',
  });
}

/// Hard cap on workflow input, sized for a small model's context window.
const workflowInputLimit = 12000;

const _languages = WorkflowOption('Language', [
  'English',
  'Hindi',
  'Hinglish',
  'Spanish',
  'French',
]);

const workflowCatalog = <Workflow>[
  Workflow(
    id: 'summarize',
    icon: Icons.short_text_rounded,
    title: 'Summarize',
    description: 'Boil long text down to the essentials.',
    template:
        'Summarize the text below in 3 to 5 short sentences. '
        'Output only the summary.\n\nText:\n{input}',
  ),
  Workflow(
    id: 'key_points',
    icon: Icons.format_list_bulleted_rounded,
    title: 'Key points',
    description: 'Pull out the main points as bullets.',
    template:
        'List the key points of the text below as a bulleted list of at most '
        '7 bullets. One short line per bullet. No intro, no outro.\n\n'
        'Text:\n{input}',
  ),
  Workflow(
    id: 'explain_simply',
    icon: Icons.lightbulb_outline_rounded,
    title: 'Explain simply',
    description: 'Plain words, as if to a curious 12 year old.',
    template:
        'Explain the text below in simple words that a 12 year old would '
        'understand. Use short sentences and one everyday example. '
        'Do not use jargon.\n\nText:\n{input}',
  ),
  Workflow(
    id: 'translate',
    icon: Icons.translate_rounded,
    title: 'Translate',
    description: 'Into English, Hindi, Hinglish and more.',
    option: _languages,
    template:
        'Translate the text below into {option}. Keep the meaning and tone. '
        'Output only the translation.\n\nText:\n{input}',
  ),
  Workflow(
    id: 'rewrite',
    icon: Icons.edit_note_rounded,
    title: 'Rewrite',
    description: 'Change the tone: formal, friendly, shorter.',
    option: WorkflowOption('Tone', [
      'Formal',
      'Friendly',
      'Shorter',
      'Persuasive',
    ]),
    template:
        'Rewrite the text below in a {option} style. Keep the meaning. '
        'Output only the rewritten text.\n\nText:\n{input}',
  ),
  Workflow(
    id: 'fix_grammar',
    icon: Icons.spellcheck_rounded,
    title: 'Fix grammar',
    description: 'Correct spelling and grammar, nothing else.',
    template:
        'Fix the spelling and grammar of the text below. Do not change the '
        'meaning or style. Output only the corrected text.\n\nText:\n{input}',
  ),
  Workflow(
    id: 'draft_reply',
    icon: Icons.reply_rounded,
    title: 'Draft a reply',
    description: 'Paste a message, get a reply ready to send.',
    inputHint: 'Paste the message you received',
    option: WorkflowOption('Tone', [
      'Friendly',
      'Formal',
      'Short',
      'Apologetic',
    ]),
    template:
        'Write a {option} reply to the message below. Keep it brief and '
        'ready to send. Output only the reply.\n\nMessage:\n{input}',
  ),
  Workflow(
    id: 'todos',
    icon: Icons.checklist_rounded,
    title: 'Extract to-dos',
    description: 'Turn notes or chats into an action list.',
    template:
        'Extract every action item from the text below as a checklist, one '
        'per line, starting with "- [ ]". Include who and when if stated. '
        'If there are none, say "No action items."\n\nText:\n{input}',
  ),
  Workflow(
    id: 'study_notes',
    icon: Icons.menu_book_outlined,
    title: 'Study notes',
    description: 'Headings, bullets and key terms to revise from.',
    template:
        'Turn the text below into concise study notes. Use short headings, '
        'bullets under each, and end with a "Key terms" list of up to 5 '
        'terms with one-line definitions.\n\nText:\n{input}',
  ),
  Workflow(
    id: 'quiz',
    icon: Icons.quiz_outlined,
    title: 'Quiz me',
    description: 'Five questions from your material, with answers.',
    template:
        'Write 5 quiz questions based on the text below. Number them. '
        'After the questions, add an "Answers" section with a short answer '
        'for each.\n\nText:\n{input}',
  ),
  Workflow(
    id: 'caption',
    icon: Icons.tag_rounded,
    title: 'Social caption',
    description: 'Three caption options with hashtags.',
    inputHint: 'Describe the post or photo',
    template:
        'Write 3 short, catchy social media captions for the post described '
        'below. Add 3 relevant hashtags to each. Number the options.\n\n'
        'Post:\n{input}',
  ),
  Workflow(
    id: 'document',
    icon: Icons.description_outlined,
    title: 'Understand a document',
    description: 'Medical report, legal text or bill in plain language.',
    inputHint: 'Paste the report, contract or bill',
    template:
        'Explain the document below in plain language. First give a 2 '
        'sentence overview, then list what each important part means, then '
        'list anything I should ask about or double check. This is not '
        'professional advice.\n\nDocument:\n{input}',
  ),
];

/// Fills `{input}` (and `{option}`) in [workflow]'s template. [option]
/// defaults to the workflow's first choice; input is trimmed and capped at
/// [workflowInputLimit]. `{option}` is replaced first so user text that
/// happens to contain the literal `{option}` is never rewritten.
String renderWorkflowPrompt(Workflow workflow, String input, [String? option]) {
  var text = input.trim();
  if (text.length > workflowInputLimit) {
    text = text.substring(0, workflowInputLimit);
  }
  final chosen = option ?? workflow.option?.defaultChoice ?? '';
  return workflow.template
      .replaceAll('{option}', chosen)
      .replaceFirst('{input}', text);
}
