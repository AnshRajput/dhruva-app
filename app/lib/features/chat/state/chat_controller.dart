/// Thread screen state + streaming (chat-spec.md §1-4, §7-8). One
/// `ChatController` per `/chat/:id` screen (family-keyed by conversation
/// id, `null` for a brand-new draft — "never a row for an empty draft" per
/// chat-spec.md §1: the conversation row is created lazily on the first
/// sent message, see [sendMessage]).
///
/// Streaming: [_flush] batches `EngineToken` deltas into the message list
/// on a `DhruvaTokens.motion.instant` (100ms) timer per chat-spec.md §3.2 —
/// never a rebuild per token. `<think>` extraction is
/// `think_tag_parser.dart`'s job; this controller just calls it per flush
/// and persists the result via `ChatRepository.updateStreamingMessage`
/// (append-only) when the re-derived split is a genuine extension of what
/// was pushed last flush (`_pushedContent`/`_pushedReasoning` hold the
/// exact last-pushed strings, not just lengths, so that's a real prefix
/// check) — falling back to `ChatRepository.setStreamingContent` (a full
/// overwrite) on the rare flush where it ISN'T an extension, e.g.
/// `think_tag_parser.dart`'s tag-stripping shrinking `content` when a
/// stray literal tag completes mid-stream (staff review N1).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;

import '../../../core/di/providers.dart';
import '../../../data/chat/chat_repository.dart';
import '../../../data/chat/models/sampling_params.dart';
import '../../../data/downloads/storage_manager.dart';
import '../../../engine_bindings/engine_service.dart';
import 'engine_session.dart';
import 'message_info_x.dart';
import 'think_tag_parser.dart';

/// Route args for a chat thread: an existing conversation, or a draft
/// (`conversationId: null`) seeded with the model the caller already
/// picked (models hub CTA / model-picker flow before the first message).
final class ChatRouteArgs {
  final int? conversationId;
  final int? initialModelId;

  const ChatRouteArgs({this.conversationId, this.initialModelId});

  @override
  bool operator ==(Object other) =>
      other is ChatRouteArgs &&
      other.conversationId == conversationId &&
      other.initialModelId == initialModelId;

  @override
  int get hashCode => Object.hash(conversationId, initialModelId);
}

final class ChatThreadState {
  /// Null until the first message is sent (draft conversation).
  final int? conversationId;
  final String title;
  final int? folderId;
  final bool pinned;
  final int? modelId;

  /// Resolved install record for [modelId], or null if unset / no longer
  /// installed (`Conversations.modelId` FKs `setNull` on model delete).
  final InstalledModelInfo? model;
  final String systemPrompt;
  final SamplingParams samplingParams;

  /// Oldest-first, unfiltered. Use [visibleMessages] for display/history —
  /// this keeps the raw list around for tests/export-adjacent debugging.
  final List<MessageInfo> messages;

  final bool isGenerating;
  final int? streamingMessageId;

  /// True between "user hit send" and the first `EngineToken` arriving —
  /// chat-spec.md §3.3's typing-indicator window.
  final bool awaitingFirstToken;

  /// Trailing-1s-window tokens/sec, chat-spec.md §3.2. 0 when not
  /// generating.
  final double liveTokPerSec;

  /// Wall-clock reasoning duration (ms) once a message's `<think>` block
  /// has closed — chat-spec.md §4's "Reasoning (12s)" label. Not persisted
  /// (no schema column); lost across app restarts, which only means an
  /// already-answered message's header falls back to no duration.
  final Map<int, int> reasoningDurationMs;

  final bool modelLoading;
  final EngineFailure? modelLoadError;

  const ChatThreadState({
    this.conversationId,
    this.title = '',
    this.folderId,
    this.pinned = false,
    this.modelId,
    this.model,
    this.systemPrompt = '',
    this.samplingParams = const SamplingParams(),
    this.messages = const [],
    this.isGenerating = false,
    this.streamingMessageId,
    this.awaitingFirstToken = false,
    this.liveTokPerSec = 0,
    this.reasoningDurationMs = const {},
    this.modelLoading = false,
    this.modelLoadError,
  });

  /// Messages with a superseded predecessor (an edited/regenerated/retried
  /// message some later row's `parentMessageId` points back at) filtered
  /// out — the thread shows only the current lineage tip of each turn.
  /// Export still sees every row via `ChatRepository.getMessages` directly.
  List<MessageInfo> get visibleMessages {
    final superseded = <int>{
      for (final m in messages)
        if (m.parentMessageId != null) m.parentMessageId!,
    };
    return messages.where((m) => !superseded.contains(m.id)).toList();
  }

  ChatThreadState copyWith({
    int? conversationId,
    String? title,
    int? folderId,
    bool clearFolderId = false,
    bool? pinned,
    int? modelId,
    InstalledModelInfo? model,
    bool clearModel = false,
    String? systemPrompt,
    SamplingParams? samplingParams,
    List<MessageInfo>? messages,
    bool? isGenerating,
    int? streamingMessageId,
    bool clearStreamingMessageId = false,
    bool? awaitingFirstToken,
    double? liveTokPerSec,
    Map<int, int>? reasoningDurationMs,
    bool? modelLoading,
    EngineFailure? modelLoadError,
    bool clearModelLoadError = false,
  }) {
    return ChatThreadState(
      conversationId: conversationId ?? this.conversationId,
      title: title ?? this.title,
      folderId: clearFolderId ? null : (folderId ?? this.folderId),
      pinned: pinned ?? this.pinned,
      modelId: modelId ?? this.modelId,
      model: clearModel ? null : (model ?? this.model),
      systemPrompt: systemPrompt ?? this.systemPrompt,
      samplingParams: samplingParams ?? this.samplingParams,
      messages: messages ?? this.messages,
      isGenerating: isGenerating ?? this.isGenerating,
      streamingMessageId: clearStreamingMessageId
          ? null
          : (streamingMessageId ?? this.streamingMessageId),
      awaitingFirstToken: awaitingFirstToken ?? this.awaitingFirstToken,
      liveTokPerSec: liveTokPerSec ?? this.liveTokPerSec,
      reasoningDurationMs: reasoningDurationMs ?? this.reasoningDurationMs,
      modelLoading: modelLoading ?? this.modelLoading,
      modelLoadError: clearModelLoadError
          ? null
          : (modelLoadError ?? this.modelLoadError),
    );
  }
}

/// `autoDispose` (staff review B1): without it, every thread a user ever
/// opens keeps its `ChatController` — full messages list, `_errorDetails`,
/// the works — alive for the whole app session, since `ref.onDispose`
/// never fires while the provider itself is kept around by a plain
/// `.family` (no listener-count-based reclamation at all). `keepAlive()`
/// is acquired only while a generation is in flight (see
/// `_runAssistantTurn`/`_resetStreamState`) so navigating away mid-stream
/// doesn't kill the background generation, but an idle thread the user
/// has simply stopped looking at gets reclaimed — `build()` re-hydrates
/// it from the repository on the next visit either way.
final chatControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ChatController, ChatThreadState, ChatRouteArgs>(
      (arg) => ChatController(args: arg),
    );

/// One flush's worth of the ≤100ms batching budget (chat-spec.md §3.2,
/// `DhruvaTokens.motion.instant`). Not read from the theme extension —
/// this is business-logic timing, not a widget animation, and the
/// controller has no `BuildContext` to fetch a `Theme.of` value from; the
/// constant is the same 100ms the token names either way.
const _flushInterval = Duration(milliseconds: 100);

class ChatController extends AsyncNotifier<ChatThreadState> {
  final ChatRouteArgs args;
  ChatController({required this.args});

  StreamSubscription<EngineEvent>? _genSub;
  Timer? _flushTimer;
  String _rawBuffer = '';

  /// The exact `content`/`reasoning` strings already persisted for the
  /// active streaming message — the full text, not just a length, so
  /// `_flush` can check a genuine `startsWith` extension (N1) rather than
  /// assuming length growth implies a compatible prefix.
  String _pushedContent = '';
  String _pushedReasoning = '';
  int? _activeAssistantId;
  DateTime? _reasoningStartedAt;
  final List<DateTime> _tokenArrivals = [];

  /// Held only while `isGenerating` (see `_runAssistantTurn`'s acquire and
  /// `_resetStreamState`'s release, the single choke point every
  /// completion/error/cancel path already runs through) — B1's
  /// autoDispose-with-keepAlive guard.
  KeepAliveLink? _keepAliveLink;

  /// Raw failure text for the "Copy error details" affordance
  /// (`EngineUnknownFailure`, chat-spec.md §8) — not persisted (`Messages`
  /// has no free-text-detail column beyond `errorKind`'s label), so a
  /// failure's exact text is only available for the current app session.
  final Map<int, String> _errorDetails = {};

  ChatRepository get _repo => ref.read(chatRepositoryProvider);

  @override
  Future<ChatThreadState> build() async {
    ref.onDispose(() {
      unawaited(_genSub?.cancel());
      _flushTimer?.cancel();
    });

    final conversationId = args.conversationId;
    if (conversationId == null) {
      final model = args.initialModelId == null
          ? null
          : await ref
                .read(storageManagerProvider)
                .getInstalledModel(args.initialModelId!);
      return ChatThreadState(modelId: model?.id, model: model);
    }

    final convo = await _repo.getConversation(conversationId);
    if (convo == null) {
      return const ChatThreadState();
    }
    final messages = await _repo.getMessages(conversationId);
    final model = convo.modelId == null
        ? null
        : await ref
              .read(storageManagerProvider)
              .getInstalledModel(convo.modelId!);
    return ChatThreadState(
      conversationId: convo.id,
      title: convo.title,
      folderId: convo.folderId,
      pinned: convo.pinned,
      modelId: convo.modelId,
      model: model,
      systemPrompt: convo.systemPrompt,
      samplingParams: convo.samplingParams,
      messages: messages,
    );
  }

  // ---- Model loading (chat-spec.md §7, §1.1) -----------------------------

  /// Loads [ChatThreadState.modelId] into the singleton engine if it isn't
  /// already loaded there. No-op with no model set. Idempotent — safe to
  /// call from the thread screen on open and again before every send.
  Future<void> ensureModelLoaded() async {
    final current = state.value;
    if (current == null || current.modelId == null || current.isGenerating) {
      return;
    }
    final engine = ref.read(engineServiceProvider);
    if (ref.read(loadedModelIdProvider) == current.modelId && engine.isLoaded) {
      return;
    }
    state = AsyncData(
      current.copyWith(modelLoading: true, clearModelLoadError: true),
    );
    try {
      final model =
          current.model ??
          await ref
              .read(storageManagerProvider)
              .getInstalledModel(current.modelId!);
      if (model == null) {
        state = AsyncData(
          state.value!.copyWith(
            modelLoading: false,
            modelLoadError: const EngineLoadFailure(
              'model is no longer installed',
            ),
          ),
        );
        return;
      }
      await engine.load(
        model.localPath,
        params: EngineLoadParams(
          contextSize: current.samplingParams.contextLength,
        ),
      );
      await ref.read(storageManagerProvider).touchLastUsed(model.id);
      ref.read(loadedModelIdProvider.notifier).set(model.id);
      state = AsyncData(
        state.value!.copyWith(
          modelLoading: false,
          model: model,
          clearModelLoadError: true,
        ),
      );
    } on EngineFailure catch (e) {
      state = AsyncData(
        state.value!.copyWith(modelLoading: false, modelLoadError: e),
      );
    }
  }

  /// Switches the conversation's model (chat-spec.md §6.1 — allowed
  /// mid-conversation, `modelId` is per-conversation not locked at
  /// creation) and immediately loads it. Blocked as a no-op while a
  /// generation is in flight — same guard as [regenerate]/[editMessage]
  /// (QA BUG-2): the in-flight reply is streaming from the engine's
  /// currently-loaded model, so flipping `modelId`/the chip mid-stream
  /// would lie about which model actually produced the answer, and
  /// `ensureModelLoaded` already refuses to touch the engine while
  /// generating anyway — this just stops the state/chip from getting
  /// ahead of that.
  Future<void> switchModel(InstalledModelInfo model) async {
    final current = state.value;
    if (current == null || current.isGenerating) return;
    if (current.conversationId != null) {
      await _repo.setModel(current.conversationId!, model.id);
    }
    state = AsyncData(
      current.copyWith(
        modelId: model.id,
        model: model,
        clearModelLoadError: true,
      ),
    );
    await ensureModelLoaded();
  }

  // ---- System prompt / sampling (chat-spec.md §5) ------------------------

  Future<void> setSystemPrompt(String value) async {
    final current = state.value;
    if (current == null) return;
    if (current.conversationId != null) {
      await _repo.setSystemPrompt(current.conversationId!, value);
    }
    state = AsyncData(current.copyWith(systemPrompt: value));
  }

  /// Throws [ValidationFailure] (via `SamplingParams.validate`) on an
  /// out-of-range value — chat-spec.md §5.2's commit-time check. The
  /// caller (the settings sheet) keeps the sheet open and shows the
  /// message inline; nothing here swallows the exception.
  Future<void> setSamplingParams(SamplingParams params) async {
    params.validate();
    final current = state.value;
    if (current == null) return;
    if (current.conversationId != null) {
      await _repo.setSamplingParams(current.conversationId!, params);
    }
    state = AsyncData(current.copyWith(samplingParams: params));
  }

  // ---- Sending / regenerating / editing -----------------------------------

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final current = state.value;
    if (current == null || current.isGenerating) return;

    var conversationId = current.conversationId;
    if (conversationId == null) {
      conversationId = await _repo.createConversation(
        modelId: current.modelId,
        systemPrompt: current.systemPrompt,
        samplingParams: current.samplingParams,
      );
      state = AsyncData(state.value!.copyWith(conversationId: conversationId));
    }

    final userMsgId = await _repo.appendMessage(
      conversationId: conversationId,
      role: MessageRole.user,
      content: trimmed,
    );
    final userMsg = MessageInfo(
      id: userMsgId,
      conversationId: conversationId,
      role: MessageRole.user,
      content: trimmed,
      status: MessageStatus.complete,
      createdAt: DateTime.now(),
    );
    final refreshedTitle = await _refreshedTitle(conversationId, current.title);
    state = AsyncData(
      state.value!.copyWith(
        title: refreshedTitle,
        messages: [...state.value!.messages, userMsg],
      ),
    );

    await _runAssistantTurn(
      conversationId: conversationId,
      historyMessages: state.value!.visibleMessages,
      parentMessageId: null,
    );
  }

  /// Re-runs [assistantMessageId]'s turn (chat-spec.md §2.4 regenerate, §8
  /// error retry — same lineage mechanism). History is everything visible
  /// strictly BEFORE that message.
  Future<void> regenerate(int assistantMessageId) async {
    final current = state.value;
    if (current == null ||
        current.isGenerating ||
        current.conversationId == null) {
      return;
    }
    final visible = current.visibleMessages;
    final index = visible.indexWhere((m) => m.id == assistantMessageId);
    if (index < 0) return;
    await _runAssistantTurn(
      conversationId: current.conversationId!,
      historyMessages: visible.sublist(0, index),
      parentMessageId: assistantMessageId,
    );
  }

  /// Edits a user message (chat-spec.md §2.4): supersedes it with a new
  /// row, then re-runs the assistant turn that followed it (superseding
  /// that reply too, if there was one).
  Future<void> editMessage(int userMessageId, String newText) async {
    final trimmed = newText.trim();
    if (trimmed.isEmpty) return;
    final current = state.value;
    if (current == null ||
        current.isGenerating ||
        current.conversationId == null) {
      return;
    }
    final visible = current.visibleMessages;
    final index = visible.indexWhere((m) => m.id == userMessageId);
    if (index < 0 || visible[index].role != MessageRole.user) return;

    final oldAssistant =
        index + 1 < visible.length &&
            visible[index + 1].role == MessageRole.assistant
        ? visible[index + 1]
        : null;

    final newUserMsgId = await _repo.appendMessage(
      conversationId: current.conversationId!,
      role: MessageRole.user,
      content: trimmed,
      parentMessageId: userMessageId,
    );
    final newUserMsg = MessageInfo(
      id: newUserMsgId,
      conversationId: current.conversationId!,
      role: MessageRole.user,
      content: trimmed,
      status: MessageStatus.complete,
      createdAt: DateTime.now(),
      parentMessageId: userMessageId,
    );
    state = AsyncData(
      state.value!.copyWith(messages: [...state.value!.messages, newUserMsg]),
    );

    await _runAssistantTurn(
      conversationId: current.conversationId!,
      historyMessages: [...visible.sublist(0, index), newUserMsg],
      parentMessageId: oldAssistant?.id,
    );
  }

  Future<void> cancel() async {
    await ref.read(engineServiceProvider).cancel();
  }

  // ---- Streaming machinery -------------------------------------------------

  Future<void> _runAssistantTurn({
    required int conversationId,
    required List<MessageInfo> historyMessages,
    required int? parentMessageId,
  }) async {
    // B1: acquire BEFORE the first `await` in this method, not after —
    // `ensureModelLoaded()` below does real async work (can load a whole
    // model), and with no active widget listener (autoDispose's normal
    // keepalive) an interrupted `sendMessage` call could otherwise get
    // this provider disposed mid-load, before generation ever visibly
    // "starts." Released on every early-return path below, and in
    // `_resetStreamState` once a real stream actually finishes.
    _keepAliveLink ??= ref.keepAlive();
    await ensureModelLoaded();
    var current = state.value!;
    if (current.modelLoadError != null) {
      _keepAliveLink?.close();
      _keepAliveLink = null;
      return;
    }
    if (current.modelId == null) {
      state = AsyncData(
        current.copyWith(
          modelLoadError: const EngineLoadFailure(
            'no model selected for this conversation',
          ),
        ),
      );
      _keepAliveLink?.close();
      _keepAliveLink = null;
      return;
    }

    state = AsyncData(
      current.copyWith(
        isGenerating: true,
        awaitingFirstToken: true,
        liveTokPerSec: 0,
        clearStreamingMessageId: true,
      ),
    );

    final assistantId = await _repo.appendMessage(
      conversationId: conversationId,
      role: MessageRole.assistant,
      content: '',
      parentMessageId: parentMessageId,
    );
    final placeholder = MessageInfo(
      id: assistantId,
      conversationId: conversationId,
      role: MessageRole.assistant,
      content: '',
      status: MessageStatus.complete,
      createdAt: DateTime.now(),
      parentMessageId: parentMessageId,
    );
    current = state.value!;
    state = AsyncData(
      current.copyWith(
        messages: [...current.messages, placeholder],
        streamingMessageId: assistantId,
      ),
    );

    _activeAssistantId = assistantId;
    _rawBuffer = '';
    _pushedContent = '';
    _pushedReasoning = '';
    _reasoningStartedAt = null;
    _tokenArrivals.clear();

    final turns = _historyTurns(historyMessages, current.systemPrompt);
    final samplingParams = current.samplingParams;
    final engineParams = EngineGenerateParams(
      maxTokens: samplingParams.maxTokens,
      temperature: samplingParams.temperature,
      topK: samplingParams.topK,
      topP: samplingParams.topP,
      seed: samplingParams.seed ?? 0xFFFFFFFF,
    );

    final completer = Completer<void>();
    _flushTimer = Timer.periodic(_flushInterval, (_) => _flush(isFinal: false));
    _genSub = ref
        .read(engineServiceProvider)
        .generate(messages: turns, params: engineParams)
        .listen(
          (event) {
            switch (event) {
              case EngineToken():
                _rawBuffer += event.text;
                _tokenArrivals.add(DateTime.now());
              case EngineCompletion():
                _onCompletion(event);
            }
          },
          onError: (Object error) {
            _onError(error);
            if (!completer.isCompleted) completer.complete();
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
        );
    await completer.future;
  }

  void _flush({required bool isFinal}) {
    final id = _activeAssistantId;
    if (id == null) return;
    final safeRaw = safeThinkPrefix(_rawBuffer, isFinal: isFinal);
    final split = splitThinkContent(safeRaw);

    if (_reasoningStartedAt == null &&
        (split.reasoningOpen || split.reasoning.isNotEmpty)) {
      _reasoningStartedAt = DateTime.now();
    }
    int? closedDurationMs;
    final current = state.value;
    if (current == null) return;
    if (_reasoningStartedAt != null &&
        !split.reasoningOpen &&
        split.reasoning.isNotEmpty &&
        !current.reasoningDurationMs.containsKey(id)) {
      closedDurationMs = DateTime.now()
          .difference(_reasoningStartedAt!)
          .inMilliseconds;
    }

    final contentChanged = split.content != _pushedContent;
    final reasoningChanged = split.reasoning != _pushedReasoning;
    if (!contentChanged &&
        !reasoningChanged &&
        closedDurationMs == null &&
        !isFinal) {
      return;
    }

    if (contentChanged || reasoningChanged) {
      // N1 (staff review): a re-derived split is NOT guaranteed to be a
      // pure extension of what's already persisted — think_tag_parser.
      // dart's tag-stripping can SHRINK `content` across a flush boundary
      // when a stray literal tag completes mid-stream. Appending a delta
      // in that case would silently diverge the persisted row from
      // in-memory state; a `startsWith` check catches it, and a rare full
      // rewrite (`setStreamingContent`) beats that silent divergence.
      final isExtension =
          split.content.startsWith(_pushedContent) &&
          split.reasoning.startsWith(_pushedReasoning);
      if (isExtension) {
        final contentDelta = split.content.substring(_pushedContent.length);
        final reasoningDelta = split.reasoning.substring(
          _pushedReasoning.length,
        );
        unawaited(
          _repo.updateStreamingMessage(
            id,
            contentDelta: contentDelta.isEmpty ? null : contentDelta,
            reasoningDelta: reasoningDelta.isEmpty ? null : reasoningDelta,
          ),
        );
      } else {
        unawaited(
          _repo.setStreamingContent(
            id,
            content: split.content,
            reasoningContent: split.reasoning.isEmpty ? null : split.reasoning,
          ),
        );
      }
      _pushedContent = split.content;
      _pushedReasoning = split.reasoning;
    }

    final now = DateTime.now();
    _tokenArrivals.removeWhere(
      (t) => now.difference(t) > const Duration(seconds: 1),
    );

    final updatedMessages = [
      for (final m in current.messages)
        if (m.id == id)
          m.copyWith(
            content: split.content,
            reasoningContent: split.reasoning.isEmpty ? null : split.reasoning,
          )
        else
          m,
    ];
    state = AsyncData(
      current.copyWith(
        messages: updatedMessages,
        awaitingFirstToken: split.content.isEmpty && split.reasoning.isEmpty,
        liveTokPerSec: _tokenArrivals.length.toDouble(),
        reasoningDurationMs: closedDurationMs == null
            ? current.reasoningDurationMs
            : {...current.reasoningDurationMs, id: closedDurationMs},
      ),
    );
  }

  void _onCompletion(EngineCompletion event) {
    _flushTimer?.cancel();
    _flush(isFinal: true);
    final id = _activeAssistantId;
    if (id == null) return;
    final status = event.reason == EngineStopReason.cancelled
        ? MessageStatus.cancelled
        : MessageStatus.complete;
    unawaited(
      _repo.finalize(
        id,
        status: status,
        tokCount: event.tokenCount,
        genMs: event.elapsedMs,
      ),
    );
    final current = state.value;
    if (current == null) return;
    final updatedMessages = [
      for (final m in current.messages)
        if (m.id == id)
          m.copyWith(
            status: status,
            tokCount: event.tokenCount,
            genMs: event.elapsedMs,
          )
        else
          m,
    ];
    state = AsyncData(
      current.copyWith(
        messages: updatedMessages,
        isGenerating: false,
        awaitingFirstToken: false,
        liveTokPerSec: 0,
        clearStreamingMessageId: true,
      ),
    );
    _resetStreamState();
  }

  void _onError(Object error) {
    _flushTimer?.cancel();
    _flush(isFinal: true);
    final failure = error is EngineFailure
        ? error
        : EngineUnknownFailure('unexpected error', cause: error);
    final id = _activeAssistantId;
    if (id != null) {
      _errorDetails[id] = failure.message;
      unawaited(
        _repo.finalize(
          id,
          status: MessageStatus.error,
          errorKind: failure.runtimeType.toString(),
        ),
      );
      final current = state.value;
      if (current != null) {
        final updatedMessages = [
          for (final m in current.messages)
            if (m.id == id)
              m.copyWith(
                status: MessageStatus.error,
                errorKind: failure.runtimeType.toString(),
              )
            else
              m,
        ];
        state = AsyncData(
          current.copyWith(
            messages: updatedMessages,
            isGenerating: false,
            awaitingFirstToken: false,
            liveTokPerSec: 0,
            clearStreamingMessageId: true,
          ),
        );
      }
    } else {
      final current = state.value;
      if (current != null) {
        state = AsyncData(
          current.copyWith(
            isGenerating: false,
            awaitingFirstToken: false,
            liveTokPerSec: 0,
            clearStreamingMessageId: true,
            modelLoadError: failure,
          ),
        );
      }
    }
    _resetStreamState();
  }

  void _resetStreamState() {
    _activeAssistantId = null;
    _rawBuffer = '';
    _pushedContent = '';
    _pushedReasoning = '';
    _reasoningStartedAt = null;
    _tokenArrivals.clear();
    _genSub = null;
    _flushTimer = null;
    _keepAliveLink?.close();
    _keepAliveLink = null;
  }

  /// Raw failure text for a finalized error message's "Copy error details"
  /// affordance (`EngineUnknownFailure`, chat-spec.md §8). Empty string
  /// (not null) once unavailable (app-restart case) — callers show a
  /// generic fallback rather than nothing.
  String errorDetailsFor(int messageId) => _errorDetails[messageId] ?? '';

  Future<String> _refreshedTitle(int conversationId, String fallback) async {
    final convo = await _repo.getConversation(conversationId);
    return convo?.title ?? fallback;
  }

  List<ChatTurn> _historyTurns(
    List<MessageInfo> messages,
    String systemPrompt,
  ) {
    return [
      if (systemPrompt.trim().isNotEmpty) ChatTurn.system(systemPrompt),
      for (final m in messages)
        if (m.status != MessageStatus.error)
          switch (m.role) {
            MessageRole.user => ChatTurn.user(m.content),
            MessageRole.assistant => ChatTurn.assistant(m.content),
            MessageRole.system => ChatTurn.system(m.content),
          },
    ];
  }
}
