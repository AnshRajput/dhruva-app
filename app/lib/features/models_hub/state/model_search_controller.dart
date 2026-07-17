/// Search screen state (T5 §2). Owns the query, the current page of
/// results, cursor pagination, and the separate "load more" failure channel
/// so a failed page-2 fetch doesn't wipe out page 1's results.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/failures/app_failure.dart';
import '../../../data/hf_api/models/hf_model_summary.dart';

final class ModelSearchState {
  final String query;
  final List<HfModelSummary> items;
  final String? nextCursor;
  final bool loadingMore;
  final AppFailure? loadMoreError;

  const ModelSearchState({
    required this.query,
    required this.items,
    required this.nextCursor,
    this.loadingMore = false,
    this.loadMoreError,
  });

  bool get hasMore => nextCursor != null;

  ModelSearchState copyWith({
    List<HfModelSummary>? items,
    String? nextCursor,
    bool clearNextCursor = false,
    bool? loadingMore,
    AppFailure? loadMoreError,
    bool clearLoadMoreError = false,
  }) {
    return ModelSearchState(
      query: query,
      items: items ?? this.items,
      nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
      loadingMore: loadingMore ?? this.loadingMore,
      loadMoreError: clearLoadMoreError
          ? null
          : (loadMoreError ?? this.loadMoreError),
    );
  }
}

final modelSearchControllerProvider =
    AsyncNotifierProvider<ModelSearchController, ModelSearchState>(
      ModelSearchController.new,
    );

class ModelSearchController extends AsyncNotifier<ModelSearchState> {
  @override
  Future<ModelSearchState> build() => _fetch('');

  Future<ModelSearchState> _fetch(String query) async {
    final client = ref.read(hfApiClientProvider);
    final result = await client.searchGgufModels(query: query);
    return ModelSearchState(
      query: query,
      items: result.items,
      nextCursor: result.nextCursor,
    );
  }

  /// Runs a fresh query, replacing the current results with a loading state
  /// — the previous query's results are stale for a new search term.
  Future<void> search(String query) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetch(query));
  }

  /// Pull-to-refresh: keeps the current list visible while re-fetching
  /// (only `RefreshIndicator`'s own spinner shows), rather than blanking the
  /// screen the way [search] does for a query change.
  Future<void> refresh() async {
    final query = state.value?.query ?? '';
    state = await AsyncValue.guard(() => _fetch(query));
  }

  /// Infinite-scroll pagination over the cursor. No-ops if there's no
  /// current page, no next cursor, or a page fetch is already in flight.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(
      current.copyWith(loadingMore: true, clearLoadMoreError: true),
    );
    try {
      final client = ref.read(hfApiClientProvider);
      final page = await client.searchGgufModels(
        query: current.query,
        cursor: current.nextCursor,
      );
      state = AsyncData(
        current.copyWith(
          items: [...current.items, ...page.items],
          nextCursor: page.nextCursor,
          clearNextCursor: page.nextCursor == null,
          loadingMore: false,
        ),
      );
    } on AppFailure catch (e) {
      state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: e));
    }
  }
}
