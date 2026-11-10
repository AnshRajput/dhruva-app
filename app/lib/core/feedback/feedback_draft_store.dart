/// Keeps what the user typed in the feedback form on the phone (app support
/// dir, never uploaded) so a mail app that takes over the screen, or Android
/// reclaiming Dhruva's process while it is away, cannot lose the report.
/// Text fields only: no attachments (cache files may vanish), no device info.
/// Cleared by "Done" after hand-off.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'feedback_report.dart';

class SavedFeedbackDraft {
  const SavedFeedbackDraft({
    required this.type,
    this.title = '',
    this.description = '',
    this.steps = '',
  });

  final FeedbackType type;
  final String title;
  final String description;
  final String steps;

  bool get isEmpty =>
      title.trim().isEmpty &&
      description.trim().isEmpty &&
      steps.trim().isEmpty;

  Map<String, Object?> toJson() => {
    'type': type.name,
    'title': title,
    'description': description,
    'steps': steps,
  };

  static SavedFeedbackDraft? fromJson(Object? j) {
    if (j is! Map) return null;
    return SavedFeedbackDraft(
      type: j['type'] == 'feature' ? FeedbackType.feature : FeedbackType.bug,
      title: j['title'] as String? ?? '',
      description: j['description'] as String? ?? '',
      steps: j['steps'] as String? ?? '',
    );
  }
}

abstract interface class FeedbackDraftStore {
  /// Never throws; null when there is nothing saved.
  Future<SavedFeedbackDraft?> load();

  /// Never throws.
  Future<void> save(SavedFeedbackDraft draft);

  /// Never throws.
  Future<void> clear();
}

final class FileFeedbackDraftStore implements FeedbackDraftStore {
  Future<File> _file() async => File(
    '${(await getApplicationSupportDirectory()).path}'
    '${Platform.pathSeparator}feedback_draft.json',
  );

  @override
  Future<SavedFeedbackDraft?> load() async {
    try {
      final f = await _file();
      if (!f.existsSync()) return null;
      return SavedFeedbackDraft.fromJson(jsonDecode(await f.readAsString()));
    } on Object {
      return null;
    }
  }

  @override
  Future<void> save(SavedFeedbackDraft draft) async {
    try {
      if (draft.isEmpty) return clear();
      await (await _file()).writeAsString(
        jsonEncode(draft.toJson()),
        flush: true,
      );
    } on Object {
      // A draft that cannot be saved must never block the form.
    }
  }

  @override
  Future<void> clear() async {
    try {
      final f = await _file();
      if (f.existsSync()) await f.delete();
    } on Object {
      // Nothing to clear.
    }
  }
}

final feedbackDraftStoreProvider = Provider<FeedbackDraftStore>(
  (ref) => FileFeedbackDraftStore(),
);
