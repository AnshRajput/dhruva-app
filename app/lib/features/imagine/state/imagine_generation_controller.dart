/// Drives one Imagine studio screen's generation run (Loop 8 T2): load the
/// picked SD checkpoint if needed, stream `ImageGenService.generate`'s
/// progress → result into UI state, persist the result to the gallery, and
/// the "enhance my prompt" trick (rewrite via the already-loaded chat LLM —
/// the master prompt's "Off Grid trick"). Draft form fields (prompt text,
/// steps/size/cfg/seed) are deliberately NOT here — they're plain widget
/// state in `ImagineStudioView`, since nothing outside that one screen reads
/// them; this controller only owns what a generation run itself produces.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/di/providers.dart';
import '../../../engine_bindings/engine_service.dart';
import '../../../imagine_engine/image_gen_service.dart';

enum GenPhase { idle, loadingModel, generating, done, cancelled, error }

@immutable
final class GenerationState {
  final GenPhase phase;
  final int? progressStep;
  final int? progressTotal;
  final Uint8List? resultPng;
  final int? resultWidth;
  final int? resultHeight;
  final String? errorMessage;

  /// True while `enhancePrompt` is awaiting the LLM's rewrite — independent
  /// of [phase], since enhancing happens before generation starts.
  final bool enhancing;

  const GenerationState({
    this.phase = GenPhase.idle,
    this.progressStep,
    this.progressTotal,
    this.resultPng,
    this.resultWidth,
    this.resultHeight,
    this.errorMessage,
    this.enhancing = false,
  });

  GenerationState copyWith({
    GenPhase? phase,
    int? progressStep,
    int? progressTotal,
    Uint8List? resultPng,
    int? resultWidth,
    int? resultHeight,
    String? errorMessage,
    bool? enhancing,
  }) => GenerationState(
    phase: phase ?? this.phase,
    progressStep: progressStep ?? this.progressStep,
    progressTotal: progressTotal ?? this.progressTotal,
    resultPng: resultPng ?? this.resultPng,
    resultWidth: resultWidth ?? this.resultWidth,
    resultHeight: resultHeight ?? this.resultHeight,
    errorMessage: errorMessage ?? this.errorMessage,
    enhancing: enhancing ?? this.enhancing,
  );
}

final imagineGenerationControllerProvider =
    NotifierProvider<ImagineGenerationController, GenerationState>(
      ImagineGenerationController.new,
    );

class ImagineGenerationController extends Notifier<GenerationState> {
  @override
  GenerationState build() => const GenerationState();

  /// Loads [modelPath] (if a different/no model is currently loaded) then
  /// streams one generation. Every failure — load or generate — lands in
  /// [GenerationState.errorMessage] with a friendly message; nothing throws
  /// past this method.
  Future<void> generate({
    required String modelPath,
    required ImageGenParams params,
  }) async {
    final service = ref.read(imageGenServiceProvider);
    state = const GenerationState(phase: GenPhase.loadingModel);
    try {
      if (!service.isLoaded) {
        await service.loadModel(modelPath);
      }
    } on ImageGenFailure catch (e) {
      state = GenerationState(
        phase: GenPhase.error,
        errorMessage: _friendlyError(e),
      );
      return;
    } catch (e) {
      state = GenerationState(
        phase: GenPhase.error,
        errorMessage: 'Could not load the image model: $e',
      );
      return;
    }

    state = GenerationState(
      phase: GenPhase.generating,
      progressStep: 0,
      progressTotal: params.steps,
    );
    try {
      await for (final event in service.generate(params)) {
        switch (event) {
          case ImageGenProgress(:final step, :final totalSteps):
            state = state.copyWith(
              progressStep: step,
              progressTotal: totalSteps,
            );
          case ImageGenResult(:final pngBytes, :final width, :final height):
            await _persist(
              pngBytes: pngBytes,
              width: width,
              height: height,
              params: params,
            );
            state = state.copyWith(
              phase: GenPhase.done,
              resultPng: pngBytes,
              resultWidth: width,
              resultHeight: height,
            );
          case ImageGenCancelled():
            state = state.copyWith(phase: GenPhase.cancelled);
        }
      }
    } on ImageGenFailure catch (e) {
      state = GenerationState(
        phase: GenPhase.error,
        errorMessage: _friendlyError(e),
      );
    } catch (e) {
      state = GenerationState(
        phase: GenPhase.error,
        errorMessage: 'Image generation failed: $e',
      );
    }
  }

  /// Cooperatively stops the in-flight run. The `generate` loop above
  /// receives the resulting [ImageGenCancelled] event itself — this doesn't
  /// set [GenerationState] directly, so there's exactly one place state
  /// transitions happen.
  Future<void> cancel() => ref.read(imageGenServiceProvider).cancel();

  /// Back to the empty form (used by "Generate another" and "Try again").
  void reset() => state = const GenerationState();

  /// Rewrites [current] into a more vivid image prompt using the already-
  /// loaded chat LLM (the "Off Grid trick" — no network, the model that's
  /// already resident for chat). Returns null (and leaves [current]
  /// untouched) when no LLM is loaded, the input is blank, or the rewrite
  /// fails for any reason — this is a best-effort assist, never a hard
  /// dependency of generation.
  Future<String?> enhancePrompt(String current) async {
    final engine = ref.read(engineServiceProvider);
    if (!engine.isLoaded || current.trim().isEmpty) return null;
    state = state.copyWith(enhancing: true);
    final buffer = StringBuffer();
    try {
      final events = engine.generate(
        prompt:
            'Rewrite the following into one vivid, detailed prompt for a '
            'text-to-image model. Reply with ONLY the rewritten prompt — one '
            'line, no preamble, no quotes.\n\n"$current"',
        params: const EngineGenerateParams(maxTokens: 120, temperature: 0.8),
      );
      await for (final event in events) {
        if (event is EngineToken) buffer.write(event.text);
      }
    } catch (_) {
      // Best-effort: leave the prompt untouched on any engine failure.
    } finally {
      state = state.copyWith(enhancing: false);
    }
    final rewritten = buffer.toString().trim();
    return rewritten.isEmpty ? null : rewritten;
  }

  Future<void> _persist({
    required Uint8List pngBytes,
    required int width,
    required int height,
    required ImageGenParams params,
  }) async {
    final dir = await ref.read(generatedImagesDirectoryProvider.future);
    final file = File(
      p.join(dir.path, 'img_${DateTime.now().microsecondsSinceEpoch}.png'),
    );
    await file.writeAsBytes(pngBytes);
    await ref
        .read(generatedImageRepositoryProvider)
        .insert(
          prompt: params.prompt,
          negativePrompt: params.negativePrompt,
          filePath: file.path,
          width: width,
          height: height,
          steps: params.steps,
          seed: params.seed,
          cfgScale: params.cfgScale,
        );
  }

  String _friendlyError(ImageGenFailure e) => switch (e) {
    ImageGenStateFailure() =>
      'Another model is loaded — close your chat first (only one big model '
          'fits in memory at a time), then try again.',
    ImageGenOutOfMemoryFailure() =>
      'Ran out of memory generating this image. Try a smaller size or '
          'fewer steps.',
    ImageGenLoadFailure() => 'Could not load the image model file.',
    ImageGenValidationFailure(:final message) => message,
    ImageGenDecodeFailure() => 'Generation failed partway through.',
    ImageGenDisposedFailure() => 'The image engine is not ready yet.',
    ImageGenUnknownFailure() => 'Image generation failed. Please try again.',
  };
}
