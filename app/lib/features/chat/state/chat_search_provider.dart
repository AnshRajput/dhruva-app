/// Cross-chat search results for a (already debounced) query — title and
/// message-content matches from `ChatRepository.search`, most recent first.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../data/chat/chat_repository.dart';

final chatSearchProvider = FutureProvider.autoDispose
    .family<List<ConversationSearchHit>, String>(
      (ref, query) => ref.watch(chatRepositoryProvider).search(query),
    );
