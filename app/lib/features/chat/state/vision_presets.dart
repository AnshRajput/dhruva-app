/// Preset prompts for the one-tap image utilities (Loop 7, LOOP-07 PLAN
/// "photo Q&A, screenshot explanation, text extraction w/ copy").
/// "Describe" needs no preset — it's just normal chat with an image
/// attached. `chat_thread_screen.dart` matches [extractTextPrompt] against a
/// user message's content to decide whether to show the "Copy text"
/// affordance on the following assistant reply — this constant is the
/// single source of truth both sides key off.
library;

const extractTextPrompt =
    'Extract all text from this image, output only the text';
