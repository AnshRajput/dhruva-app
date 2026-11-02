/// The seam between the brief and the on-device model, so tests never touch
/// the engine. The real writer shares the app-wide engine with chat through
/// the same lease, so it never loads or generates underneath a chat turn or a
/// speed test (ADR-001: one active session). Inference runs in the engine's
/// own isolate, never on the root isolate.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/engine_session.dart';
import '../../../core/di/providers.dart';
import '../../../core/di/speed_providers.dart';
import '../../../engine_bindings/engine_service.dart';

enum BriefModelStatus {
  /// No chat model is installed: the brief shows its facts as a list.
  none,

  /// A model is installed but not in memory yet.
  idle,

  /// A model is loaded and can write now.
  ready,
}

/// Why a brief could not be written; [message] is user-ready.
final class BriefUnavailable implements Exception {
  const BriefUnavailable(this.message);
  final String message;
  @override
  String toString() => 'BriefUnavailable: $message';
}

abstract interface class BriefWriter {
  Future<BriefModelStatus> status();

  /// Loads the most recently used chat model when none is in memory. Throws
  /// [BriefUnavailable].
  Future<void> prepare();

  /// One completion for [prompt]. Throws [BriefUnavailable].
  Future<String> write({required String system, required String prompt});
}

class EngineBriefWriter implements BriefWriter {
  EngineBriefWriter(this._ref);
  final Ref _ref;

  static const _timeout = Duration(seconds: 120);

  @override
  Future<BriefModelStatus> status() async {
    if (_ref.read(engineServiceProvider).isLoaded) {
      return BriefModelStatus.ready;
    }
    final usable = await _ref.read(storageManagerProvider).listTextModels();
    return usable.isEmpty ? BriefModelStatus.none : BriefModelStatus.idle;
  }

  @override
  Future<void> prepare() async {
    final engine = _ref.read(engineServiceProvider);
    if (engine.isLoaded) return;
    final lease = _ref.read(engineLeaseProvider);
    if (lease.speedTestRunning || lease.chatBusy) {
      throw const BriefUnavailable(
        'Your phone is busy with another task. Pull down to try again in a '
        'moment.',
      );
    }
    final storage = _ref.read(storageManagerProvider);
    final models = await storage.listTextModels();
    if (models.isEmpty) {
      throw const BriefUnavailable('Download a model to write your brief.');
    }
    final model = models.first; // most recently used first
    lease.chatEnter();
    try {
      await engine.load(
        model.localPath,
        params: EngineLoadParams(mmprojPath: model.mmprojPath),
      );
      await storage.touchLastUsed(model.id);
      _ref.read(loadedModelIdProvider.notifier).set(model.id);
    } on EngineFailure {
      throw const BriefUnavailable(
        "Your model didn't load. Open Settings > Models to try another one.",
      );
    } finally {
      lease.chatLeave();
    }
  }

  @override
  Future<String> write({required String system, required String prompt}) async {
    final engine = _ref.read(engineServiceProvider);
    final lease = _ref.read(engineLeaseProvider);
    if (!engine.isLoaded) {
      throw const BriefUnavailable('The model is not ready yet.');
    }
    if (lease.speedTestRunning || lease.chatBusy) {
      throw const BriefUnavailable(
        'Your phone is busy with another task. Pull down to try again in a '
        'moment.',
      );
    }
    lease.chatEnter();
    final out = StringBuffer();
    try {
      await for (final e
          in engine
              .generate(
                messages: [ChatTurn.system(system), ChatTurn.user(prompt)],
                params: const EngineGenerateParams(
                  maxTokens: 260,
                  temperature: 0.3,
                  topP: 0.9,
                ),
              )
              .timeout(_timeout)) {
        if (e is EngineToken) out.write(e.text);
      }
    } on TimeoutException {
      unawaited(engine.cancel());
      throw const BriefUnavailable(
        'Writing took too long. Pull down to try again.',
      );
    } on EngineFailure {
      throw const BriefUnavailable(
        "The model couldn't write your brief. Pull down to try again.",
      );
    } finally {
      lease.chatLeave();
    }
    return out.toString();
  }
}

final briefWriterProvider = Provider<BriefWriter>(EngineBriefWriter.new);
