/// The "Search in" choice for one Ask thread: Auto (rules pick sources from
/// the question as you type) or an explicit set. Lives beside the thread, not
/// inside `ChatThreadState`, so toggling a chip never rebuilds the message
/// list. The controller reads it when a turn starts.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/connectors/ask_sources.dart';
import 'chat_controller.dart' show ChatRouteArgs;

final class AskSelectionState {
  final AskSourceSelection selection;

  /// What is typed in the composer right now (drives Auto's live preview).
  final String draft;
  const AskSelectionState({
    this.selection = AskSourceSelection.autoSelection,
    this.draft = '',
  });
}

class AskSelectionNotifier extends Notifier<AskSelectionState> {
  AskSelectionNotifier(this.args);
  final ChatRouteArgs args;

  @override
  AskSelectionState build() {
    final pinned = args.initialSources;
    // A prefilled route (`/ask/new?sources=...`) arrives with those sources
    // pinned, so the user sees exactly what will be searched before sending.
    return AskSelectionState(
      selection: pinned.isEmpty && args.focusItemIds.isEmpty
          ? AskSourceSelection.autoSelection
          : AskSourceSelection(auto: false, pinned: pinned),
      draft: args.initialDraft ?? '',
    );
  }

  void setDraft(String text) {
    if (text == state.draft) return;
    state = AskSelectionState(selection: state.selection, draft: text);
  }

  /// Back to Auto.
  void chooseAuto() => state = AskSelectionState(draft: state.draft);

  /// Tapping a source: leaves Auto, starting from what Auto would search for
  /// the current draft, then flips [source].
  void toggle(AskSource source, {required Set<AskSource> currentlyResolved}) {
    final base = state.selection.auto
        ? currentlyResolved
        : state.selection.pinned;
    final next = {...base};
    if (!next.remove(source)) next.add(source);
    state = AskSelectionState(
      selection: AskSourceSelection(auto: false, pinned: next),
      draft: state.draft,
    );
  }
}

final askSelectionProvider = NotifierProvider.autoDispose
    .family<AskSelectionNotifier, AskSelectionState, ChatRouteArgs>(
      AskSelectionNotifier.new,
    );
