/// G2 (Loop 6) picker-pollution guard, re-verified for `features/chat`'s
/// copy of `installedModelsProvider` — the model picker sheet
/// (`model_picker_sheet.dart`) and `conversation_list_screen.dart` both
/// watch this provider, and a `sherpa-voice/` row here would eventually
/// reach `EngineService.load()` with a whisper/piper onnx bundle instead of
/// a GGUF. No test previously exercised this filter directly (only the
/// downstream widgets, indirectly, via installed-model fixtures that never
/// happened to include a voice row).
library;

import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/features/chat/state/installed_models_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a sherpa-voice/ installed row is filtered out of the chat model '
      'picker list', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.installedModels)
        .insert(
          InstalledModelsCompanion.insert(
            repoId: 'bartowski/Some-Model-GGUF',
            fileName: 'model.gguf',
            sizeBytes: 100,
            localPath: '/tmp/model.gguf',
            downloadedAt: DateTime.utc(2026, 7, 17),
          ),
        );
    await db
        .into(db.installedModels)
        .insert(
          InstalledModelsCompanion.insert(
            repoId: 'sherpa-voice/whisper-tiny',
            fileName: 'sherpa-onnx-whisper-tiny.tar.bz2',
            sizeBytes: 111000000,
            localPath: '/tmp/whisper.tar.bz2',
            downloadedAt: DateTime.utc(2026, 7, 17),
          ),
        );

    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    final models = await container.read(installedModelsProvider.future);

    expect(models, hasLength(1));
    expect(models.single.repoId, 'bartowski/Some-Model-GGUF');
    expect(models.any((m) => m.repoId.startsWith('sherpa-voice/')), isFalse);
  });
}
