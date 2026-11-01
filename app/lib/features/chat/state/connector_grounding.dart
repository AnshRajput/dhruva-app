/// Grounds an Ask question on items from the connectors (calendar, contacts,
/// files, notifications) the thread has pinned. The matching items go into the
/// one delimited `<sources>` block (`data/connectors/sources_block.dart`), so
/// whatever other people wrote in an event, a notification or a file can never
/// read as an instruction; the model's reply only ever becomes text on screen.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/connector_providers.dart';
import '../../../data/connectors/connector.dart';
import '../../../data/connectors/sources_block.dart';

/// Characters of items quoted into one prompt (a 4k-token context has room
/// for about 12k).
const connectorGroundingBudgetChars = 3500;

/// Pure: the prompt for [question] over [block].
String connectorGroundedPrompt(String question, SourcesBlock block) {
  if (block.isEmpty) {
    return '$question\n\n'
        'Nothing on this phone matched, in the sources you picked. Say so '
        'plainly and suggest connecting or syncing the source. Do not guess.';
  }
  return '${block.text}\n\nQuestion: $question\n\n'
      'Answer only from the sources above and cite them like [1]. If they do '
      'not contain the answer, say so.';
}

/// The items to quote: the focus event first, then upcoming events when the
/// calendar is pinned, then the best keyword matches across the pinned
/// sources. Deduplicated, in that order.
Future<List<ConnectorItem>> gatherGroundingItems(
  Ref ref, {
  required String question,
  required Set<String> sources,
  int? focusEventId,
}) async {
  final store = ref.read(connectorStoreProvider);
  final items = <ConnectorItem>[];
  final seen = <int>{};
  void add(Iterable<ConnectorItem> more) {
    for (final i in more) {
      if (seen.add(i.id)) items.add(i);
    }
  }

  var search = question;
  if (focusEventId != null) {
    final focus = await store.itemsByIds([focusEventId]);
    add(focus);
    if (focus.isNotEmpty) {
      final f = focus.first;
      // The event's own words drive the search; they never enter the prompt
      // outside the sources block.
      search = [
        f.title,
        for (final p in f.people) p.name ?? p.email ?? '',
      ].join(' ');
    }
  } else if (sources.contains(ConnectorIds.calendar)) {
    add(await store.watchNextEvents(store.now, limit: 8).first);
  }
  final index = await ref.read(searchIndexProvider.future);
  final hits = await index.search(search, limit: 8, sources: sources);
  add([for (final h in hits) h.item]);
  return items;
}

/// Builds the grounded prompt, or falls back to "nothing matched" wording.
Future<String> groundOnConnectors(
  Ref ref, {
  required String question,
  required Set<String> sources,
  int? focusEventId,
}) async {
  List<ConnectorItem> items;
  try {
    items = await gatherGroundingItems(
      ref,
      question: question,
      sources: sources,
      focusEventId: focusEventId,
    );
  } on Object {
    // A broken index must not break chat: answer as an ungrounded question
    // that says it could not look.
    items = const [];
  }
  return connectorGroundedPrompt(
    question,
    buildSourcesBlock(items, maxChars: connectorGroundingBudgetChars),
  );
}
