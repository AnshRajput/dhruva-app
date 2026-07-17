import 'hf_model_summary.dart';

/// One page of `HfApiClient.searchGgufModels`. `nextCursor` is null when
/// there is no further page (or the response carried no `Link: rel="next"`
/// header — HF's cursor pagination is opt-in per query).
final class HfSearchResult {
  final List<HfModelSummary> items;
  final String? nextCursor;
  const HfSearchResult({required this.items, required this.nextCursor});
}
