/// The Imagine studio form (Loop 8 T2): prompt + optional negative prompt,
/// enhance-prompt (via the loaded chat LLM), steps/size/cfg/seed controls
/// with `ImageGenParams`' own defaults, Generate/Cancel, and the result
/// actions (save/share, generate another). One `ImagineCanvas` shows
/// idle/loading/progress/result/error — see its own doc for why phases live
/// in one widget instead of five.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/di/providers.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../imagine_engine/image_gen_service.dart';
import '../state/imagine_generation_controller.dart';
import '../widgets/imagine_canvas.dart';

/// `ImageGenParams.width/height` presets — multiples of 64, matching
/// `checkImageGenParams`' constraint, and small enough for the "30s-2min on
/// your device" expectation the master prompt sets.
const _sizePresets = <(int, int)>[(384, 384), (512, 512), (512, 768)];

class ImagineStudioView extends ConsumerStatefulWidget {
  final File modelFile;
  const ImagineStudioView({super.key, required this.modelFile});

  @override
  ConsumerState<ImagineStudioView> createState() => _ImagineStudioViewState();
}

class _ImagineStudioViewState extends ConsumerState<ImagineStudioView> {
  final _promptCtrl = TextEditingController();
  final _negativeCtrl = TextEditingController();

  // ImageGenParams' own defaults (image_gen_service.dart) — one place to
  // change if a future loop retunes them, this screen just mirrors.
  static const _defaults = ImageGenParams(prompt: '');
  int _steps = _defaults.steps;
  double _cfgScale = _defaults.cfgScale;
  int _seed = _defaults.seed;
  (int, int) _size = (_defaults.width, _defaults.height);

  @override
  void dispose() {
    _promptCtrl.dispose();
    _negativeCtrl.dispose();
    super.dispose();
  }

  bool get _engineLoaded => ref.read(engineServiceProvider).isLoaded;

  Future<void> _enhance() async {
    final controller = ref.read(imagineGenerationControllerProvider.notifier);
    final enhanced = await controller.enhancePrompt(_promptCtrl.text);
    if (enhanced != null && mounted) {
      setState(() => _promptCtrl.text = enhanced);
    }
  }

  void _generate() {
    if (_promptCtrl.text.trim().isEmpty) return;
    ref
        .read(imagineGenerationControllerProvider.notifier)
        .generate(
          modelPath: widget.modelFile.path,
          params: ImageGenParams(
            prompt: _promptCtrl.text.trim(),
            negativePrompt: _negativeCtrl.text.trim(),
            steps: _steps,
            width: _size.$1,
            height: _size.$2,
            cfgScale: _cfgScale,
            seed: _seed,
          ),
        );
  }

  Future<void> _shareResult(Uint8List png) async {
    final dir = await ref.read(generatedImagesDirectoryProvider.future);
    final file = File(
      '${dir.path}/share_${DateTime.now().microsecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(png);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: 'Made with Dhruva AI'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final state = ref.watch(imagineGenerationControllerProvider);
    final controller = ref.read(imagineGenerationControllerProvider.notifier);
    final busy =
        state.phase == GenPhase.loadingModel ||
        state.phase == GenPhase.generating;

    return SingleChildScrollView(
      padding: EdgeInsets.all(tokens.spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ImagineCanvas(state: state, onCancel: controller.cancel),
          SizedBox(height: tokens.spacing.sm),
          Text(
            'Runs 100% on your device — expect 30s-2min per image.',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: tokens.spacing.md),
          if (state.phase == GenPhase.done)
            _ResultActions(
              onSaveShare: () => _shareResult(state.resultPng!),
              onGenerateAnother: controller.reset,
            )
          else ...[
            TextField(
              controller: _promptCtrl,
              enabled: !busy,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Prompt',
                hintText: 'a lone pole star over a still mountain lake…',
                suffixIcon: IconButton(
                  icon: state.enhancing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_fix_high_outlined),
                  tooltip: _engineLoaded
                      ? 'Enhance prompt with your loaded chat model'
                      : 'Load a chat model to enhance prompts',
                  onPressed: (_engineLoaded && !state.enhancing && !busy)
                      ? _enhance
                      : null,
                ),
              ),
            ),
            SizedBox(height: tokens.spacing.sm),
            TextField(
              controller: _negativeCtrl,
              enabled: !busy,
              minLines: 1,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Negative prompt (optional)',
                hintText: 'blurry, low quality',
              ),
            ),
            SizedBox(height: tokens.spacing.md),
            Text('Size', style: theme.textTheme.titleSmall),
            SizedBox(height: tokens.spacing.xs),
            Wrap(
              spacing: tokens.spacing.xs,
              children: [
                for (final preset in _sizePresets)
                  ChoiceChip(
                    label: Text('${preset.$1}×${preset.$2}'),
                    selected: _size == preset,
                    onSelected: busy
                        ? null
                        : (_) => setState(() => _size = preset),
                  ),
              ],
            ),
            _StudioSlider(
              label: 'Steps',
              value: _steps.toDouble(),
              min: 4,
              max: 50,
              divisions: 46,
              enabled: !busy,
              onChanged: (v) => setState(() => _steps = v.round()),
            ),
            _StudioSlider(
              label: 'CFG scale',
              value: _cfgScale,
              min: 1,
              max: 20,
              divisions: 38,
              enabled: !busy,
              onChanged: (v) => setState(() => _cfgScale = v),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _seed == -1 ? 'Seed: random' : 'Seed: $_seed',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(
                          () => _seed = _seed == -1
                              ? DateTime.now().millisecondsSinceEpoch &
                                    0x7fffffff
                              : -1,
                        ),
                  child: Text(_seed == -1 ? 'Fix seed' : 'Randomize'),
                ),
              ],
            ),
            SizedBox(height: tokens.spacing.sm),
            FilledButton.icon(
              onPressed: busy ? null : _generate,
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(busy ? 'Generating…' : 'Generate'),
            ),
            if (state.phase == GenPhase.error) ...[
              SizedBox(height: tokens.spacing.sm),
              TextButton(
                onPressed: controller.reset,
                child: const Text('Try again'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ResultActions extends StatelessWidget {
  final VoidCallback onSaveShare;
  final VoidCallback onGenerateAnother;
  const _ResultActions({
    required this.onSaveShare,
    required this.onGenerateAnother,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onSaveShare,
            icon: const Icon(Icons.ios_share_outlined),
            label: const Text('Save / Share'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed: onGenerateAnother,
            icon: const Icon(Icons.refresh),
            label: const Text('Generate another'),
          ),
        ),
      ],
    );
  }
}

class _StudioSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final bool enabled;
  final ValueChanged<double> onChanged;

  const _StudioSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.spacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: theme.textTheme.titleSmall),
              Text(
                value == value.roundToDouble()
                    ? value.round().toString()
                    : value.toStringAsFixed(1),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}
