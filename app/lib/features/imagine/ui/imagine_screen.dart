/// Imagine's entry screen (Loop 8 T2, D1): the RAM gate first (Amendment —
/// "flagged OFF below the RAM floor" covers the whole feature, gallery
/// included, not just Generate — a device that can't run SD today almost
/// certainly never saved an image from it either), then a two-tab shell
/// (Create / Gallery) once the device clears the floor.
///
/// Reached from Settings (`features/settings/ui/settings_screen.dart`'s
/// Imagine tile) rather than a 5th bottom-nav destination — same
/// discoverable-but-not-a-primary-tab precedent Voice's hands-free screen
/// sets (`/voice/handsfree`, reached from inside a chat thread, not its own
/// tab). ImagineMock.astro's `BottomNav active="you"` maps onto this app's
/// actual nav as the Settings tab (its closest real analog to the mock's
/// account-shaped "You" destination).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../imagine_engine/sd_image_gen_service.dart';
import '../state/device_memory_provider.dart';
import '../state/sd_models_provider.dart';
import '../widgets/no_sd_model_view.dart';
import '../widgets/ram_gate_view.dart';
import 'imagine_gallery_view.dart';
import 'imagine_studio_view.dart';

class ImagineScreen extends ConsumerWidget {
  const ImagineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memory = ref.watch(imagineDeviceMemoryProvider);
    return switch (memory) {
      AsyncData(:final value) =>
        value.totalBytes >= SdImageGenService.recommendedMinRamBytes
            ? const _ImagineHome()
            : ImagineRamGateView(
                deviceRamBytes: value.totalBytes,
                floorBytes: SdImageGenService.recommendedMinRamBytes,
              ),
      AsyncError() => Scaffold(
        appBar: AppBar(title: const Text('Imagine')),
        body: const Center(child: Text("Couldn't read this device's memory.")),
      ),
      _ => Scaffold(
        appBar: AppBar(title: const Text('Imagine')),
        body: const Center(child: CircularProgressIndicator()),
      ),
    };
  }
}

class _ImagineHome extends StatelessWidget {
  const _ImagineHome();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Imagine'),
          actions: [
            Padding(
              padding: EdgeInsets.only(right: tokens.spacing.md),
              child: Center(
                child: Chip(
                  label: const Text('SD · on-device'),
                  visualDensity: VisualDensity.compact,
                  labelStyle: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Create'),
              Tab(text: 'Gallery'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_ImagineCreateTab(), ImagineGalleryView()],
        ),
      ),
    );
  }
}

class _ImagineCreateTab extends ConsumerWidget {
  const _ImagineCreateTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final models = ref.watch(installedSdModelsProvider);
    return switch (models) {
      AsyncData(:final value) when value.isEmpty => const NoSdModelView(),
      AsyncData(:final value) => ImagineStudioView(modelFile: value.first),
      AsyncError() => const Center(
        child: Text("Couldn't read installed image models."),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}
