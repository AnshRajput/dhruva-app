import 'dart:io';

import 'package:dhruva/core/di/providers.dart';
import 'package:dhruva/features/imagine/state/sd_models_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory sdDir;

  setUp(() async {
    sdDir = await Directory.systemTemp.createTemp('imagine_sd_models_test');
  });

  tearDown(() async {
    await sdDir.delete(recursive: true);
  });

  test('an empty directory reports no installed models', () async {
    final container = ProviderContainer(
      overrides: [sdModelsDirectoryProvider.overrideWith((ref) async => sdDir)],
    );
    addTearDown(container.dispose);

    final result = await container.read(installedSdModelsProvider.future);
    expect(result, isEmpty);
  });

  test('lists checkpoint files already on disk', () async {
    File('${sdDir.path}/model.safetensors').writeAsBytesSync([1]);
    final container = ProviderContainer(
      overrides: [sdModelsDirectoryProvider.overrideWith((ref) async => sdDir)],
    );
    addTearDown(container.dispose);

    final result = await container.read(installedSdModelsProvider.future);
    expect(result, hasLength(1));
    expect(result.single.path, endsWith('model.safetensors'));
  });

  // importSdCheckpoint takes a WidgetRef (it's only ever called from a
  // button's onPressed), so it's exercised through a minimal widget harness
  // rather than a raw ProviderContainer.
  testWidgets('importSdCheckpoint copies the file in and refreshes the list', (
    tester,
  ) async {
    final sourceDir = await Directory.systemTemp.createTemp(
      'imagine_sd_source_test',
    );
    addTearDown(() => sourceDir.delete(recursive: true));
    final source = File('${sourceDir.path}/picked.ckpt')
      ..writeAsBytesSync([9, 9, 9]);

    List<File>? observed;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sdModelsDirectoryProvider.overrideWith((ref) async => sdDir),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              observed = ref.watch(installedSdModelsProvider).value;
              return ElevatedButton(
                onPressed: () => importSdCheckpoint(ref, source),
                child: const Text('import'),
              );
            },
          ),
        ),
      ),
    );
    expect(observed, isEmpty);

    await tester.tap(find.text('import'));
    await tester.pumpAndSettle();

    expect(observed, hasLength(1));
    expect(File(observed!.single.path).readAsBytesSync(), [9, 9, 9]);
  });
}
