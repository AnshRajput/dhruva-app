/// Pure `<think>...</think>` extraction (chat-spec.md §4). The repository
/// stores `content`/`reasoningContent` separately (see `ChatRepository.
/// updateStreamingMessage`), so the UI never parses raw text itself — this
/// is the one place that does, feeding `ChatController`'s streaming loop.
///
/// Tolerant of a model that never emits the closing tag (chat-spec.md
/// doesn't cover this case — the Loop-4 brief does: treat the rest of the
/// message as reasoning until either the tag closes or generation ends).
/// Only the FIRST `<think>` is recognized as an opener — a second literal
/// `<think>` after a closed block is vanishingly rare in practice and would
/// otherwise re-open reasoning mid-answer, which no model in this
/// convention does.
///
/// ponytail: QA BUG-3 — a second/nested `<think>...</think>` pair (past the
/// first recognized one) is NOT parsed into `reasoning`; its text lands in
/// `content` like any other prose. What IS fixed: the literal tag markers
/// themselves are always stripped out of `content` before it's returned, so
/// a user never sees raw `<think>`/`</think>` text in the answer — only the
/// (unlabeled) text that was between them. Full multi-block reasoning
/// capture is a real upgrade (parse every pair, not just the first) —
/// do it if a model in this app's catalog is actually observed emitting
/// multiple reasoning passes in one turn; today none does.
library;

const thinkOpenTag = '<think>';
const thinkCloseTag = '</think>';

/// [raw] split into `reasoning` (text between the tags, or from the opener
/// to end-of-string if unclosed) and `content` (everything else,
/// concatenated). [reasoningOpen] is true while inside an unclosed opener.
final class ThinkSplit {
  final String reasoning;
  final String content;
  final bool reasoningOpen;

  const ThinkSplit({
    required this.reasoning,
    required this.content,
    required this.reasoningOpen,
  });
}

ThinkSplit splitThinkContent(String raw) {
  final openIdx = raw.indexOf(thinkOpenTag);
  if (openIdx < 0) {
    return ThinkSplit(reasoning: '', content: raw, reasoningOpen: false);
  }
  final before = raw.substring(0, openIdx);
  final afterOpenIdx = openIdx + thinkOpenTag.length;
  final closeIdx = raw.indexOf(thinkCloseTag, afterOpenIdx);
  if (closeIdx < 0) {
    return ThinkSplit(
      reasoning: raw.substring(afterOpenIdx),
      content: before,
      reasoningOpen: true,
    );
  }
  final reasoning = raw.substring(afterOpenIdx, closeIdx);
  final after = raw.substring(closeIdx + thinkCloseTag.length);
  return ThinkSplit(
    reasoning: reasoning,
    // `before` never contains a tag (openIdx is the FIRST occurrence in
    // `raw`), but `after` can hold a second/nested pair's literal markers
    // — strip them so they never render as raw tag text (QA BUG-3); the
    // text between them still surfaces as plain content, see the library
    // doc's ponytail note on the multi-block ceiling.
    content: (before + after)
        .replaceAll(thinkOpenTag, '')
        .replaceAll(thinkCloseTag, ''),
    reasoningOpen: false,
  );
}

/// How many trailing characters of a raw streaming buffer might still be an
/// in-progress prefix of `<think>`/`</think>` and so must NOT be classified
/// yet (a flush mid-tag would otherwise commit those chars to the wrong
/// side and never be able to take them back — `content = content || ?` in
/// `ChatRepository` is append-only). One less than the longer tag's length.
const thinkTagHoldback = thinkCloseTag.length - 1;

/// The prefix of [raw] that's safe to classify right now: everything except
/// the last [thinkTagHoldback] characters, unless [isFinal] (no more data is
/// coming, so nothing is held back).
String safeThinkPrefix(String raw, {required bool isFinal}) {
  if (isFinal || raw.length <= thinkTagHoldback) return raw;
  return raw.substring(0, raw.length - thinkTagHoldback);
}
