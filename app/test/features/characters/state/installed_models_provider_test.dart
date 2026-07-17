/// G2 (Loop 6) picker-pollution guard, re-verified for `features/characters`'
/// copy of `installedModelsProvider` (the character form's "default model"
/// picker, `character_form_screen.dart`) — deliberate duplication of
/// `features/chat`'s copy per ADR-002 (no `features/` importing
/// `features/`), so it needs its own regression test rather than relying
/// on the chat-side one.
library;

import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/data/db/database.dart';
import 'package:dhruva/features/characters/state/installed_models_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a sherpa-voice/ installed row is filtered out of the character '
      'default-model picker list', () async {
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
            repoId: 'sherpa-voice/piper-en-amy-low',
            fileName: 'vits-piper-en_US-amy-low.tar.bz2',
            sizeBytes: 67000000,
            localPath: '/tmp/amy.tar.bz2',
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
