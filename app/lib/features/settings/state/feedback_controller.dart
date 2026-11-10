/// State + actions for Settings > Report a bug / Request a feature. All the
/// logic lives here (and in `core/feedback`); the screen only renders it.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/crash/crash_log.dart';
import '../../../core/feedback/feedback_draft_store.dart';
import '../../../core/feedback/feedback_report.dart';
import '../../../core/feedback/feedback_sender.dart';
import '../app_info.dart';
import 'feedback_inputs.dart';

/// Route -> form: `/settings/feedback?type=bug|feature[&crash=1]`.
typedef FeedbackEntry = ({FeedbackType type, bool fromCrash});

FeedbackEntry feedbackEntryFromQuery(Map<String, String> q) => (
  type: q['type'] == 'feature' ? FeedbackType.feature : FeedbackType.bug,
  fromCrash: q['crash'] == '1',
);

@immutable
class FeedbackFormState {
  const FeedbackFormState({
    required this.type,
    this.title = '',
    this.description = '',
    this.steps = '',
    this.attachments = const [],
    this.includeDevice = true,
    this.includeCrash = false,
    this.showErrors = false,
    this.attachError,
    this.sendError,
    this.busy = false,
    this.handoff,
    this.restoreSeq = 0,
  });

  /// Bumped when a saved draft was loaded into the fields, so the screen can
  /// copy the text into its text controllers.
  final int restoreSeq;

  final FeedbackType type;
  final String title;
  final String description;
  final String steps;
  final List<FeedbackAttachment> attachments;
  final bool includeDevice;
  final bool includeCrash;
  final bool showErrors;
  final String? attachError;
  final String? sendError;
  final bool busy;

  /// Set once the draft was handed to the mail app / share sheet.
  final FeedbackHandoff? handoff;

  String? get titleError => showErrors ? validateFeedbackTitle(title) : null;
  String? get descriptionError =>
      showErrors ? validateFeedbackDescription(description) : null;
  bool get valid =>
      validateFeedbackTitle(title) == null &&
      validateFeedbackDescription(description) == null;

  FeedbackFormState copyWith({
    FeedbackType? type,
    String? title,
    String? description,
    String? steps,
    List<FeedbackAttachment>? attachments,
    bool? includeDevice,
    bool? includeCrash,
    bool? showErrors,
    String? Function()? attachError,
    String? Function()? sendError,
    bool? busy,
    FeedbackHandoff? Function()? handoff,
    int? restoreSeq,
  }) => FeedbackFormState(
    restoreSeq: restoreSeq ?? this.restoreSeq,
    type: type ?? this.type,
    title: title ?? this.title,
    description: description ?? this.description,
    steps: steps ?? this.steps,
    attachments: attachments ?? this.attachments,
    includeDevice: includeDevice ?? this.includeDevice,
    includeCrash: includeCrash ?? this.includeCrash,
    showErrors: showErrors ?? this.showErrors,
    attachError: attachError != null ? attachError() : this.attachError,
    sendError: sendError != null ? sendError() : this.sendError,
    busy: busy ?? this.busy,
    handoff: handoff != null ? handoff() : this.handoff,
  );
}

/// Stands in for the real device info in the preview while it loads.
const _pendingInfo = FeedbackDeviceInfo(
  phoneModel: '',
  os: '',
  appVersion: '',
  appBuild: '',
);

class FeedbackFormController extends Notifier<FeedbackFormState> {
  FeedbackFormController(this.entry);
  final FeedbackEntry entry;

  @override
  FeedbackFormState build() {
    Future.microtask(_restore);
    return FeedbackFormState(type: entry.type, includeCrash: entry.fromCrash);
  }

  /// Loads a saved draft of the same type, if the user has not typed yet.
  Future<void> _restore() async {
    final saved = await ref.read(feedbackDraftStoreProvider).load();
    if (!ref.mounted || saved == null || saved.type != entry.type) return;
    if (state.title.isNotEmpty ||
        state.description.isNotEmpty ||
        state.steps.isNotEmpty) {
      return;
    }
    state = state.copyWith(
      title: saved.title,
      description: saved.description,
      steps: saved.steps,
      restoreSeq: state.restoreSeq + 1,
    );
  }

  void _save() => unawaited(
    ref
        .read(feedbackDraftStoreProvider)
        .save(
          SavedFeedbackDraft(
            type: state.type,
            title: state.title,
            description: state.description,
            steps: state.steps,
          ),
        ),
  );

  void setType(FeedbackType t) {
    state = state.copyWith(type: t);
    _save();
  }

  void setTitle(String v) {
    state = state.copyWith(title: v);
    _save();
  }

  void setDescription(String v) {
    state = state.copyWith(description: v);
    _save();
  }

  void setSteps(String v) {
    state = state.copyWith(steps: v);
    _save();
  }

  /// "Done" after hand-off: the report is in the user's hands, drop the copy.
  Future<void> finish() => ref.read(feedbackDraftStoreProvider).clear();

  void setIncludeDevice(bool v) => state = state.copyWith(includeDevice: v);
  void setIncludeCrash(bool v) => state = state.copyWith(includeCrash: v);

  void removeAttachment(int i) => state = state.copyWith(
    attachments: [...state.attachments]..removeAt(i),
    attachError: () => null,
  );

  Future<void> addMedia() async {
    final room = feedbackMaxAttachments - state.attachments.length;
    if (room <= 0) {
      state = state.copyWith(attachError: () => feedbackTooManyFiles);
      return;
    }
    try {
      final picked = await ref.read(feedbackMediaPickerProvider).pick(room);
      if (picked.isEmpty) return;
      final err = checkAttachmentLimits(state.attachments, picked);
      state = err == null
          ? state.copyWith(
              attachments: [...state.attachments, ...picked],
              attachError: () => null,
            )
          : state.copyWith(attachError: () => err);
    } on FeedbackMediaDenied {
      state = state.copyWith(
        attachError: () =>
            'Photo access is off. Allow it in system settings to attach files.',
      );
    } on Object {
      state = state.copyWith(
        attachError: () => "Couldn't open your photos. Try again.",
      );
    }
  }

  /// Primary action: the email draft (falls back to the share sheet if the
  /// plugin reports no mail app).
  Future<void> send() => _handOff(share: false);

  /// Secondary action, always available: the system share sheet.
  Future<void> share() => _handOff(share: true);

  Future<void> _handOff({required bool share}) async {
    if (state.busy) return;
    if (!state.valid) {
      state = state.copyWith(showErrors: true);
      return;
    }
    state = state.copyWith(busy: true, sendError: () => null);
    try {
      final info = state.includeDevice
          ? await ref.read(feedbackDeviceInfoProvider.future)
          : null;
      final crashes = state.includeCrash
          ? await ref.read(crashReportsProvider.future)
          : null;
      final report = buildFeedbackReport(
        FeedbackDraft(
          type: state.type,
          title: state.title,
          description: state.description,
          steps: state.steps,
          attachments: state.attachments,
          deviceInfo: info,
          crashRecords: crashes,
        ),
        version: appVersion,
      );
      // The mail app takes the screen and Android may not bring Dhruva back
      // to this exact moment, so the confirmation (and the saved draft) must
      // already be in place BEFORE the intent launches.
      _save();
      state = state.copyWith(
        busy: false,
        handoff: () =>
            share ? FeedbackHandoff.shareSheet : FeedbackHandoff.emailDraft,
      );
      final transport = ref.read(feedbackTransportProvider);
      final how = share
          ? await shareFeedback(report, transport)
          : await sendFeedback(report, transport);
      if (ref.mounted) state = state.copyWith(handoff: () => how);
      if (state.includeCrash) {
        await ref.read(crashLogProvider).markSeen();
        ref.invalidate(unseenCrashReportsProvider);
      }
    } on Object {
      if (!ref.mounted) return;
      state = state.copyWith(
        busy: false,
        handoff: () => null,
        sendError: () =>
            "Couldn't open your email app or the share sheet. Try again.",
      );
    }
  }
}

final feedbackFormProvider = NotifierProvider.autoDispose
    .family<FeedbackFormController, FeedbackFormState, FeedbackEntry>(
      FeedbackFormController.new,
    );

/// The one-line "this is exactly what will be shared" text, live.
final feedbackPreviewProvider = Provider.autoDispose
    .family<String, FeedbackEntry>((ref, entry) {
      final s = ref.watch(feedbackFormProvider(entry));
      final info = s.includeDevice
          ? ref.watch(feedbackDeviceInfoProvider).value ?? _pendingInfo
          : null;
      final crashes = s.includeCrash
          ? ref.watch(crashReportsProvider).value
          : null;
      return feedbackPreview(
        FeedbackDraft(
          type: s.type,
          title: s.title,
          description: s.description,
          steps: s.steps,
          attachments: s.attachments,
          deviceInfo: info,
          crashRecords: crashes,
        ),
      );
    });
