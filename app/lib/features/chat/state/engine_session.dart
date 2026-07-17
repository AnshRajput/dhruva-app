/// Tracks which installed model (by `InstalledModels.id`) is currently
/// loaded into the app-wide singleton `EngineService` (ADR-001: one active
/// session). `ChatController` reads/writes this so opening a second
/// conversation that uses the same model skips a redundant reload, and a
/// conversation using a different model knows it must load before
/// generating.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

final loadedModelIdProvider = NotifierProvider<LoadedModelIdNotifier, int?>(
  LoadedModelIdNotifier.new,
);

class LoadedModelIdNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void set(int? modelId) => state = modelId;
}
