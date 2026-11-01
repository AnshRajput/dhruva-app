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
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;

import '../../../core/device_health/device_guard_policy.dart';
import '../../../core/device_health/device_health.dart';
import '../../../core/device_health/device_health_provider.dart';
import '../../../core/di/connector_providers.dart';
import '../../../core/di/providers.dart';
import '../../../core/di/speed_providers.dart';
import '../../../core/profile/user_profile.dart';
import '../../../core/safety/safety_guard.dart';
import '../../../data/chat/chat_repository.dart';
import '../../../data/chat/models/sampling_params.dart';
import '../../../data/connectors/connector.dart' show ConnectorItem;
import '../../../data/connectors/sources_block.dart' show buildSourcesBlock;
import '../../../data/docs/bm25.dart';
import '../../../data/docs/document_extractor.dart';
import '../../../data/docs/document_repository.dart';
import '../../../data/docs/grounding.dart';
import '../../../data/downloads/storage_manager.dart';
import '../../../docs/document_picker.dart' show PickedDocument;
import '../../../engine_bindings/engine_service.dart';
import 'engine_session.dart';
import 'message_info_x.dart';
import 'think_tag_parser.dart';

/// Route args for a chat thread: an existing conversation, or a draft
/// (`conversationId: null`) seeded with the model the caller already
/// picked (models hub CTA / model-picker flow before the first message) —
/// or, per Loop 5, seeded from a character (`characterId`): the persona
/// becomes the system prompt, the character's default model/sampling apply,
/// and its greeting (if any) is posted as the first assistant message. See
/// [ChatController.build]'s `conversationId == null` branch.
final class ChatRouteArgs {
  final int? conversationId;
  final int? initialModelId;
  final int? characterId;

  /// A prompt to seed the first turn of a brand-new draft with — the
  /// onboarding "Try asking" chips route `/chat/new?prompt=...` here so the
  /// first chat auto-sends that message (chat_thread_screen.dart), turning
  /// the guided flow's success step into a real streaming reply instead of an
  /// empty conversation list. Only meaningful when [conversationId] is null.
  final String? initialPrompt;

  /// Connector items (a Library file's sections, an Inbox notification) this
  /// new chat is about. Their text reaches the model only inside the
  /// delimited sources block (`data/connectors/sources_block.dart`), never as
  /// instructions. Only meaningful when [conversationId] is null.
  final List<int> sourceItemIds;

  const ChatRouteArgs({
    this.conversationId,
    this.initialModelId,
    this.characterId,
    this.initialPrompt,
    this.sourceItemIds = const [],
  });

  @override
  bool operator ==(Object other) =>
      other is ChatRouteArgs &&
      other.conversationId == conversationId &&
      other.initialModelId == initialModelId &&
      other.characterId == characterId &&
      other.initialPrompt == initialPrompt &&
      listEquals(other.sourceItemIds, sourceItemIds);

  @override
  int get hashCode => Object.hash(
    conversationId,
    initialModelId,
    characterId,
    initialPrompt,
    Object.hashAll(sourceItemIds),
  );
}

final class ChatThreadState {
  /// Null until the first message is sent (draft conversation).
  final int? conversationId;
  final String title;
  final int? folderId;
  final bool pinned;
  final int? modelId;

  /// The character (if any) this thread was started with — chat-spec.md's
  /// AppBar shows this character's name/avatar in place of the model chip
  /// when set (Loop 5). See `data/characters/character_repository.dart`.
  final int? characterId;

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

  /// True once the engine confirms the loaded model's projector initialised
  /// (`EngineService.isMultimodal`, Loop 7 gate G3) — drives the composer's
  /// attach-button gate. False before the first successful [ensureModelLoaded]
  /// and for any text-only model.
  final bool isMultimodal;

  /// Image bytes attached to a user turn, keyed by that message's id — same
  /// "not persisted, session-only" precedent as [reasoningDurationMs]: no
  /// `Messages` schema column carries image data this loop, so a message's
  /// attached image is lost across an app restart (upgrade path: a drift
  /// migration adding an image column, if a future loop needs it to
  /// survive). Populated by [sendMessage], read by `chat_thread_screen.dart`
  /// to render the thumbnail in [MessageBubble] and by [_historyTurns] to
  /// carry the image into the engine's [ChatTurn].
  final Map<int, Uint8List> attachedImages;

  /// Documents attached to this conversation (chat with a document), oldest
  /// first. A negative [DocumentInfo.id] is a draft chat's extracted-but-not-
  /// yet-stored document; it is saved when the first message is sent.
  final List<DocumentInfo> documents;

  /// File name while a picked document is being read (chip shows "Reading…").
  final String? extractingDocName;

  /// Plain-language reason the last attach failed, shown inline above the
  /// composer until dismissed.
  final String? documentError;

  /// Assistant messages cut short by the battery & heat guard (thermal
  /// critical). The partial text is kept; the thread shows a note under it.
  /// Session-only, same precedent as [reasoningDurationMs].
  final Set<int> heatStoppedMessageIds;

  /// When the turn in flight started warming up (send tapped, model maybe
  /// loading, no first token yet); null otherwise. Drives the "Warming up
  /// (model name) · 4 s" row.
  final DateTime? warmingSince;

  /// True once a turn has waited [firstTokenTimeoutProvider] with no first
  /// token: the thread offers Stop / Try again in plain words.
  final bool firstTokenTimedOut;

  /// Titles of the connector items this chat was opened about (see
  /// [ChatRouteArgs.sourceItemIds]); session-only like a draft's documents.
  final List<String> sourceTitles;

  const ChatThreadState({
    this.conversationId,
    this.title = '',
    this.folderId,
    this.pinned = false,
    this.modelId,
    this.characterId,
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
    this.isMultimodal = false,
    this.attachedImages = const {},
    this.documents = const [],
    this.extractingDocName,
    this.documentError,
    this.heatStoppedMessageIds = const {},
    this.warmingSince,
    this.firstTokenTimedOut = false,
    this.sourceTitles = const [],
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
    int? characterId,
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
    bool? isMultimodal,
    Map<int, Uint8List>? attachedImages,
    List<DocumentInfo>? documents,
    String? extractingDocName,
    bool clearExtractingDocName = false,
    String? documentError,
    bool clearDocumentError = false,
    Set<int>? heatStoppedMessageIds,
    DateTime? warmingSince,
    bool clearWarmingSince = false,
    bool? firstTokenTimedOut,
  }) {
    return ChatThreadState(
      conversationId: conversationId ?? this.conversationId,
      title: title ?? this.title,
      folderId: clearFolderId ? null : (folderId ?? this.folderId),
      pinned: pinned ?? this.pinned,
      modelId: modelId ?? this.modelId,
      characterId: characterId ?? this.characterId,
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
      isMultimodal: isMultimodal ?? this.isMultimodal,
      attachedImages: attachedImages ?? this.attachedImages,
      documents: documents ?? this.documents,
      extractingDocName: clearExtractingDocName
          ? null
          : (extractingDocName ?? this.extractingDocName),
      documentError: clearDocumentError
          ? null
          : (documentError ?? this.documentError),
      heatStoppedMessageIds:
          heatStoppedMessageIds ?? this.heatStoppedMessageIds,
      warmingSince: clearWarmingSince
          ? null
          : (warmingSince ?? this.warmingSince),
      firstTokenTimedOut: firstTokenTimedOut ?? this.firstTokenTimedOut,
      sourceTitles: sourceTitles,
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

/// How long a turn may wait for its first token before the thread offers
/// Stop / Try again (D3). A constant, overridable in tests.
const kFirstTokenTimeout = Duration(seconds: 60);

final firstTokenTimeoutProvider = Provider<Duration>(
  (ref) => kFirstTokenTimeout,
);

/// The follow-up the model gets when the user taps Continue on a reply that
/// was stopped, cut short or errored. The partial reply is the previous
/// assistant turn; the new text is appended to the same message.
const _continuePrompt =
    'Continue from exactly where you stopped. Do not repeat anything you '
    'already wrote.';

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
  Timer? _firstTokenTimer;
  String _rawBuffer = '';

  /// True while the turn in flight is a "Continue" of an existing reply: new
  /// text is appended after [_seedRaw] (the reply so far) on the same row.
  bool _continuing = false;
  String _seedRaw = '';

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

  /// The in-flight [ensureModelLoaded] future, or null when no load is
  /// running. `engine.load()` takes seconds and there's no other reentrancy
  /// lock (WS3 defect): on a fresh chat the screen-open load and a
  /// suggested-prompt tap (`sendMessage` → `_runAssistantTurn` →
  /// `ensureModelLoaded`) both pass the `isGenerating`/`loadedModelIdProvider`
  /// checks while the first load is still awaiting, and each would spawn a
  /// second inference isolate + load the model into RAM twice — a realistic
  /// OOM on the RAM-tiered devices this app targets. Deduping every caller
  /// (screen open, send, `switchModel`, error recovery) onto the same future
  /// means the second call awaits the first instead of starting another.
  Future<void>? _loadInFlight;

  /// Synchronous "a generation is being set up or is in flight" latch (WS3
  /// defect). `ChatThreadState.isGenerating` can't be the guard here: it's
  /// only flipped true AFTER `ensureModelLoaded()` returns (and
  /// `_ensureModelLoaded` itself early-returns when `isGenerating` is true, so
  /// it can't be set earlier), leaving the whole multi-second cold-model load
  /// window with `isGenerating == false`. During that window a second send /
  /// switch / regenerate would sail past the state guard and start a second
  /// concurrent turn on the singleton engine (double generate, leaked
  /// flush-timer). This flag is set synchronously at the entry of every
  /// generation path BEFORE the first `await`, checked by all of them, and
  /// cleared on every exit path — so exactly one turn is ever in flight.
  bool get _turnInFlight => _turnInFlightFlag;
  set _turnInFlight(bool value) {
    if (value == _turnInFlightFlag) return;
    _turnInFlightFlag = value;
    // Mirror into the app-wide engine lease so a speed test never starts
    // while a turn is in flight.
    value ? _lease.chatEnter() : _lease.chatLeave();
  }

  bool _turnInFlightFlag = false;

  /// Captured in [build] (a plain object, safe to use after provider disposal).
  late EngineLease _lease;

  /// Set when the streamed reply tripped [SafetyGuard.blocks]: further
  /// tokens are dropped and the reply is replaced by the notice.
  bool _outputBlocked = false;

  /// Raw failure text for the "Copy error details" affordance
  /// (`EngineUnknownFailure`, chat-spec.md §8) — not persisted (`Messages`
  /// has no free-text-detail column beyond `errorKind`'s label), so a
  /// failure's exact text is only available for the current app session.
  final Map<int, String> _errorDetails = {};

  /// True while this controller holds a [deviceHealthProvider] polling lease
  /// (only while a generation is in flight).
  bool _holdsHealthLease = false;

  /// The assistant message the heat guard asked the engine to stop.
  int? _heatStoppedId;

  ChatRepository get _repo => ref.read(chatRepositoryProvider);
  DocumentRepository get _docs => ref.read(documentRepositoryProvider);

  bool _disposed = false;

  /// Extracted documents of a draft chat, waiting for the conversation row
  /// (created lazily on the first send) to exist. Keyed by the negative
  /// temp id shown in [ChatThreadState.documents].
  final Map<int, ExtractedDocument> _pendingDocs = {};
  var _nextTempDocId = -1;

  /// Retrieval corpus + BM25 index for this conversation's documents, built
  /// on first question and dropped whenever the document set changes.
  List<StoredChunk>? _corpus;
  Bm25Index? _corpusIndex;

  /// Connector items this chat was opened about, loaded once for a new chat
  /// (a Library file, an Inbox notification).
  List<ConnectorItem> _pinned = const [];

  Future<void> _loadPinned() async {
    if (args.sourceItemIds.isEmpty) return;
    try {
      _pinned = await ref
          .read(connectorStoreProvider)
          .itemsByIds(args.sourceItemIds);
    } catch (_) {
      // The chat still works, just without the pinned source.
    }
  }

  List<String> _pinnedTitles() {
    final seen = <String>[];
    for (final i in _pinned) {
      final t = i.title.trim().isEmpty ? i.kind.name : i.title.trim();
      if (!seen.contains(t)) seen.add(t);
    }
    return seen;
  }

  /// The user's question wrapped with the pinned items' text in a delimited,
  /// numbered sources block (see `buildSourcesBlock`): the only way connector
  /// text reaches a prompt. Null when nothing is pinned.
  String? _groundInPinned(List<MessageInfo> historyMessages) {
    if (_pinned.isEmpty) return null;
    final question = historyMessages
        .where((m) => m.role == MessageRole.user)
        .lastOrNull
        ?.content;
    if (question == null) return null;
    // The sections most relevant to the question first, so a long file keeps
    // the part that answers it inside the size budget.
    final index = Bm25Index([for (final i in _pinned) i.body]);
    final order = <int>{
      for (final h in index.search(question)) h.index,
      for (var i = 0; i < _pinned.length; i++) i,
    };
    final block = buildSourcesBlock(
      [for (final i in order) _pinned[i]],
      maxChars: 7000,
      maxItemChars: 2500,
    );
    return 'Answer the question using only the sources below. If the answer '
        'is not in them, say so; do not guess or use outside knowledge. Cite '
        'sources like [1].\n\n${block.text}\n\nQuestion: $question';
  }

  /// Citations offered to the reply being generated (empty when ungrounded).
  List<DocSource> _activeSources = const [];

  @override
  Future<ChatThreadState> build() async {
    _lease = ref.read(engineLeaseProvider);
    // Keep the "About the user" block warm so a send reads it synchronously
    // (never waits on disk); main() also warms it at startup.
    ref.listen(userContextProvider, (_, _) {});
    ref.onDispose(() {
      _disposed = true;
      unawaited(_genSub?.cancel());
      _flushTimer?.cancel();
      _firstTokenTimer?.cancel();
      _releaseHealthLease();
    });
    // Heat guard: a critical reading while this thread is streaming stops the
    // reply gracefully. The poller only runs while a generation holds a lease.
    ref.listen(deviceHealthProvider, (_, health) => _stopIfTooHot(health));

    final conversationId = args.conversationId;
    if (conversationId == null) {
      if (args.characterId != null) {
        return _buildFromCharacter(args.characterId!, args.initialModelId);
      }
      final storage = ref.read(storageManagerProvider);
      // No explicit model (workflows, share / "Ask Dhruva AI", the New chat
      // shortcut): use the most-recently-used installed model rather than
      // dead-ending on "No model installed yet" when one is installed.
      final model = args.initialModelId == null
          ? (await storage.listInstalledModels()).firstOrNull
          : await storage.getInstalledModel(args.initialModelId!);
      await _loadPinned();
      return ChatThreadState(
        modelId: model?.id,
        model: model,
        sourceTitles: _pinnedTitles(),
      );
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
      characterId: convo.characterId,
      model: model,
      systemPrompt: convo.systemPrompt,
      samplingParams: convo.samplingParams,
      messages: messages,
      documents: await _docs.listDocuments(convo.id),
    );
  }

  /// Loop 5: starts a NEW conversation bound to character [characterId] —
  /// the persona (`CharacterChatContext.systemPrompt`) becomes the
  /// conversation's system prompt (so it reaches the engine on the very
  /// first turn via [_historyTurns], same mechanism every conversation's
  /// system prompt already uses), the character's default model/sampling
  /// apply (falling back to [fallbackModelId] — the caller's own pick — when
  /// the character has none), and its greeting, if any, is posted as the
  /// first assistant message.
  ///
  /// Unlike an ordinary draft, this conversation row is created immediately
  /// rather than lazily on first send — a greeting is content the user
  /// should see before typing anything, so there's nothing to defer. If the
  /// character has since been deleted (`chatContextFor` returns null), this
  /// degrades to an ordinary model-only draft rather than erroring.
  Future<ChatThreadState> _buildFromCharacter(
    int characterId,
    int? fallbackModelId,
  ) async {
    final chatContext = await ref
        .read(characterRepositoryProvider)
        .chatContextFor(characterId);
    if (chatContext == null) {
      final model = fallbackModelId == null
          ? null
          : await ref
                .read(storageManagerProvider)
                .getInstalledModel(fallbackModelId);
      return ChatThreadState(modelId: model?.id, model: model);
    }

    final samplingParams = chatContext.samplingParams ?? const SamplingParams();
    final resolvedModelId = chatContext.defaultModelId ?? fallbackModelId;
    final model = resolvedModelId == null
        ? null
        : await ref
              .read(storageManagerProvider)
              .getInstalledModel(resolvedModelId);

    final newConversationId = await _repo.createConversation(
      modelId: model?.id,
      characterId: characterId,
      systemPrompt: chatContext.systemPrompt,
      samplingParams: samplingParams,
    );
    _signalConversationListChanged();

    var messages = const <MessageInfo>[];
    final greeting = chatContext.greeting?.trim();
    if (greeting != null && greeting.isNotEmpty) {
      final greetingId = await _repo.appendMessage(
        conversationId: newConversationId,
        role: MessageRole.assistant,
        content: greeting,
      );
      messages = [
        MessageInfo(
          id: greetingId,
          conversationId: newConversationId,
          role: MessageRole.assistant,
          content: greeting,
          status: MessageStatus.complete,
          createdAt: DateTime.now(),
        ),
      ];
    }

    return ChatThreadState(
      conversationId: newConversationId,
      characterId: characterId,
      modelId: model?.id,
      model: model,
      systemPrompt: chatContext.systemPrompt,
      samplingParams: samplingParams,
      messages: messages,
    );
  }

  // ---- Model loading (chat-spec.md §7, §1.1) -----------------------------

  /// Loads [ChatThreadState.modelId] into the singleton engine if it isn't
  /// already loaded there. No-op with no model set. Idempotent — safe to
  /// call from the thread screen on open and again before every send.
  ///
  /// Reentrancy-safe: concurrent callers share one in-flight load (see
  /// [_loadInFlight]) so a second call can never start a second
  /// `engine.load()`/isolate while the first is still awaiting.
  Future<void> ensureModelLoaded() {
    return _loadInFlight ??= () {
      _lease.chatEnter();
      return _ensureModelLoaded().whenComplete(() {
        _loadInFlight = null;
        _lease.chatLeave();
      });
    }();
  }

  Future<void> _ensureModelLoaded() async {
    final current = state.value;
    if (current == null || current.modelId == null || current.isGenerating) {
      return;
    }
    // A speed test owns the engine (it swaps the loaded model): don't load or
    // generate underneath it. Surfaces as the "model is busy" error card.
    if (_lease.speedTestRunning) {
      state = AsyncData(
        current.copyWith(
          modelLoadError: const EngineStateFailure('a speed test is running'),
        ),
      );
      return;
    }
    final engine = ref.read(engineServiceProvider);
    if (ref.read(loadedModelIdProvider) == current.modelId && engine.isLoaded) {
      // Already the loaded model (e.g. a second thread reusing it) — still
      // sync this controller's own isMultimodal flag, since a fresh
      // ChatController.build() never touched the engine to learn it.
      if (current.isMultimodal != engine.isMultimodal) {
        state = AsyncData(current.copyWith(isMultimodal: engine.isMultimodal));
      }
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
          // Loop 7 T1 HANDOFF: a vision model's row carries the paired
          // mmproj projector's path once downloaded (null for a text-only
          // model, or a vision model whose projector hasn't landed yet —
          // `InstalledModelInfo.needsProjector`). Passing it here is what
          // flips `EngineService.isMultimodal` on after a successful load.
          mmprojPath: model.mmprojPath,
        ),
      );
      await ref.read(storageManagerProvider).touchLastUsed(model.id);
      ref.read(loadedModelIdProvider.notifier).set(model.id);
      state = AsyncData(
        state.value!.copyWith(
          modelLoading: false,
          model: model,
          isMultimodal: engine.isMultimodal,
          clearModelLoadError: true,
        ),
      );
    } on EngineFailure catch (e) {
      state = AsyncData(
        state.value!.copyWith(
          modelLoading: false,
          modelLoadError: e,
          isMultimodal: false,
        ),
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
    if (current == null || current.isGenerating || _turnInFlight) return;
    // Hold the same in-flight latch across the switch's own load: a send
    // fired while the new model is still loading must not start a turn on a
    // half-swapped model, and a second switch must not race this one.
    _turnInFlight = true;
    try {
      if (current.conversationId != null) {
        await _repo.setModel(current.conversationId!, model.id);
      }
      state = AsyncData(
        current.copyWith(
          modelId: model.id,
          model: model,
          clearModelLoadError: true,
          // Placeholder until ensureModelLoaded confirms the new model's real
          // capability — avoids a one-frame stale "attach button visible"
          // flash carried over from the previous model.
          isMultimodal: false,
        ),
      );
      await ensureModelLoaded();
    } finally {
      _turnInFlight = false;
    }
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

  /// UX-hardening A2/BUG3: a conversation row was just created here — nudge
  /// the kept-alive `conversationListControllerProvider` (via the shared
  /// revision signal, ADR-002-safe) so the new chat shows up without a
  /// pull-to-refresh. Deferred with a microtask because `_buildFromCharacter`
  /// creates its row during `build()`, and Riverpod forbids mutating another
  /// provider mid-build.
  void _signalConversationListChanged() {
    unawaited(
      Future<void>.microtask(() {
        try {
          ref.read(conversationListRevisionProvider.notifier).bump();
        } catch (_) {
          // ponytail: controller disposed before the microtask ran (autoDispose
          // race) — the list re-reads from the DB on its next build anyway.
        }
      }),
    );
  }

  // ---- Sending / regenerating / editing -----------------------------------

  /// [imageBytes] (Loop 7): an already-downscaled image attached to this
  /// turn (`composer.dart` does the downscale before calling this). Allowed
  /// alongside empty [text] — "just a photo" is a valid send. The image is
  /// always recorded (so it still renders in the bubble even in an odd edge
  /// case), but [_runAssistantTurn] only forwards it to the engine when
  /// `isMultimodal` is confirmed true AFTER that turn's own
  /// [ensureModelLoaded] call — never based on this stale pre-load state,
  /// which is why the guard doesn't live here: the composer's attach button
  /// being gated on `isMultimodal` should already prevent an image reaching
  /// a text-only model, but a stale in-flight image from a just-swapped
  /// model must not get sent to the engine either.
  Future<void> sendMessage(String text, {Uint8List? imageBytes}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && imageBytes == null) return;
    final current = state.value;
    if (current == null || current.isGenerating || _turnInFlight) return;
    // Latch synchronously, before the first await (createConversation /
    // appendMessage below, then the model load in _runAssistantTurn) — so a
    // second send fired during any of those windows is dropped here.
    _turnInFlight = true;

    var conversationId = current.conversationId;
    if (conversationId == null) {
      conversationId = await _repo.createConversation(
        modelId: current.modelId,
        systemPrompt: current.systemPrompt,
        samplingParams: current.samplingParams,
      );
      state = AsyncData(state.value!.copyWith(conversationId: conversationId));
      _signalConversationListChanged();
    }
    await _persistPendingDocuments(conversationId);

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
        attachedImages: imageBytes == null
            ? state.value!.attachedImages
            : {...state.value!.attachedImages, userMsgId: imageBytes},
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
        _turnInFlight ||
        current.conversationId == null) {
      return;
    }
    final visible = current.visibleMessages;
    final index = visible.indexWhere((m) => m.id == assistantMessageId);
    if (index < 0) return;
    _turnInFlight = true;
    await _runAssistantTurn(
      conversationId: current.conversationId!,
      historyMessages: visible.sublist(0, index),
      parentMessageId: assistantMessageId,
    );
  }

  /// Resumes the latest reply when it was stopped, cut short, heat-stopped
  /// or errored part-way (D1): the model is shown the partial reply and
  /// asked to carry on, and the new text is appended to the same message.
  /// No-op for anything but the newest, non-empty, unfinished assistant reply.
  Future<void> continueMessage(int assistantMessageId) async {
    final current = state.value;
    if (current == null ||
        current.isGenerating ||
        _turnInFlight ||
        current.conversationId == null) {
      return;
    }
    final visible = current.visibleMessages;
    if (visible.isEmpty || visible.last.id != assistantMessageId) return;
    final m = visible.last;
    if (m.role != MessageRole.assistant ||
        m.status == MessageStatus.complete ||
        m.content.trim().isEmpty) {
      return;
    }
    _turnInFlight = true;
    await _runAssistantTurn(
      conversationId: current.conversationId!,
      historyMessages: visible,
      parentMessageId: null,
      continueMessageId: assistantMessageId,
    );
  }

  /// "Try again" after [ChatThreadState.firstTokenTimedOut]: stops the stuck
  /// turn, then re-runs it (a Continue stays a Continue).
  Future<void> retryStalled() async {
    final id = state.value?.streamingMessageId;
    if (id == null) return;
    final wasContinuing = _continuing;
    await cancel();
    // ponytail: poll for the cancel to land, same as useLighterModel.
    for (var i = 0; i < 100 && _turnInFlight; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (wasContinuing) {
      await continueMessage(id);
    } else {
      await regenerate(id);
    }
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
        _turnInFlight ||
        current.conversationId == null) {
      return;
    }
    final visible = current.visibleMessages;
    final index = visible.indexWhere((m) => m.id == userMessageId);
    if (index < 0 || visible[index].role != MessageRole.user) return;
    _turnInFlight = true;

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

  // ---- Documents (chat with a document) -----------------------------------

  /// At most this many documents per conversation; keeps the retrieval
  /// corpus (and the memory it needs) bounded.
  static const maxDocuments = 3;

  /// Opens the file picker, reads the chosen PDF/TXT/MD off the root
  /// isolate, and attaches it: stored straight away in an existing
  /// conversation, held in memory for a draft until its first message. A
  /// failure is surfaced as [ChatThreadState.documentError], never thrown.
  Future<void> attachDocument() async {
    final current = state.value;
    if (current == null || current.extractingDocName != null) return;
    if (current.documents.length >= maxDocuments) {
      state = AsyncData(
        current.copyWith(
          documentError:
              'You can attach up to $maxDocuments documents to one chat. '
              'Remove one first.',
        ),
      );
      return;
    }
    PickedDocument? picked;
    try {
      picked = await ref.read(documentPickerProvider).pickDocument();
    } catch (_) {
      if (_disposed) return;
      state = AsyncData(
        state.value!.copyWith(documentError: "Couldn't open the file picker."),
      );
      return;
    }
    if (picked == null || _disposed) return;
    state = AsyncData(
      state.value!.copyWith(
        extractingDocName: picked.name,
        clearDocumentError: true,
      ),
    );
    try {
      final doc = await ref.read(documentExtractorProvider)(
        picked.path,
        picked.name,
      );
      if (_disposed) return;
      final cur = state.value!;
      final DocumentInfo info;
      if (cur.conversationId != null) {
        info = await _docs.addDocument(cur.conversationId!, doc);
      } else {
        final tempId = _nextTempDocId--;
        _pendingDocs[tempId] = doc;
        info = _infoFor(tempId, 0, doc);
      }
      _corpus = null;
      _corpusIndex = null;
      if (_disposed) return;
      state = AsyncData(
        state.value!.copyWith(
          documents: [...state.value!.documents, info],
          clearExtractingDocName: true,
        ),
      );
    } on DocumentException catch (e) {
      if (_disposed) return;
      state = AsyncData(
        state.value!.copyWith(
          documentError: e.message,
          clearExtractingDocName: true,
        ),
      );
    } catch (_) {
      if (_disposed) return;
      state = AsyncData(
        state.value!.copyWith(
          documentError: "Couldn't read that file.",
          clearExtractingDocName: true,
        ),
      );
    }
  }

  /// Detaches a document from this conversation (and deletes its stored
  /// text). Past replies keep their citations.
  Future<void> removeDocument(int documentId) async {
    final current = state.value;
    if (current == null) return;
    if (documentId < 0) {
      _pendingDocs.remove(documentId);
    } else {
      await _docs.removeDocument(documentId);
    }
    _corpus = null;
    _corpusIndex = null;
    if (_disposed) return;
    state = AsyncData(
      state.value!.copyWith(
        documents: [
          for (final d in state.value!.documents)
            if (d.id != documentId) d,
        ],
      ),
    );
  }

  void dismissDocumentError() {
    final current = state.value;
    if (current == null || current.documentError == null) return;
    state = AsyncData(current.copyWith(clearDocumentError: true));
  }

  DocumentInfo _infoFor(int id, int conversationId, ExtractedDocument doc) {
    return DocumentInfo(
      id: id,
      conversationId: conversationId,
      name: doc.name,
      mime: doc.mime,
      pageCount: doc.pageCount,
      charCount: doc.charCount,
      createdAt: DateTime.now(),
    );
  }

  /// Saves a draft chat's held documents once its conversation row exists.
  Future<void> _persistPendingDocuments(int conversationId) async {
    if (_pendingDocs.isEmpty) return;
    final saved = <int, DocumentInfo>{};
    for (final entry in _pendingDocs.entries.toList()) {
      saved[entry.key] = await _docs.addDocument(conversationId, entry.value);
    }
    _pendingDocs.clear();
    _corpus = null;
    _corpusIndex = null;
    final current = state.value;
    if (current == null || _disposed) return;
    state = AsyncData(
      current.copyWith(
        documents: [for (final d in current.documents) saved[d.id] ?? d],
      ),
    );
  }

  /// Retrieves the excerpts for the turn's question and returns the grounded
  /// prompt that replaces it, or null when no document is attached.
  Future<GroundedPrompt?> _groundQuestion({
    required int conversationId,
    required List<MessageInfo> historyMessages,
    required String systemPrompt,
    required SamplingParams samplingParams,
  }) async {
    if (state.value!.documents.isEmpty) return null;
    final question = historyMessages
        .where((m) => m.role == MessageRole.user)
        .lastOrNull
        ?.content;
    if (question == null) return null;
    final corpus = _corpus ??= await _docs.chunksFor(conversationId);
    final index = _corpusIndex ??= Bm25Index([for (final c in corpus) c.text]);
    final promptChars =
        SafetyGuard.systemInstruction.length +
        systemPrompt.length +
        historyMessages.fold<int>(0, (n, m) => n + m.content.length);
    final excerpts = selectExcerpts(
      chunks: corpus,
      index: index,
      question: question,
      budgetChars: excerptBudgetChars(
        contextTokens: samplingParams.contextLength,
        maxAnswerTokens: samplingParams.maxTokens,
        promptChars: promptChars,
      ),
    );
    return buildGroundedPrompt(question: question, excerpts: excerpts);
  }

  // ---- Streaming machinery -------------------------------------------------

  Future<void> _runAssistantTurn({
    required int conversationId,
    required List<MessageInfo> historyMessages,
    required int? parentMessageId,
    int? continueMessageId,
  }) async {
    // B1: acquire BEFORE the first `await` in this method, not after —
    // `ensureModelLoaded()` below does real async work (can load a whole
    // model), and with no active widget listener (autoDispose's normal
    // keepalive) an interrupted `sendMessage` call could otherwise get
    // this provider disposed mid-load, before generation ever visibly
    // "starts." Released on every early-return path below, and in
    // `_resetStreamState` once a real stream actually finishes.
    _keepAliveLink ??= ref.keepAlive();
    // Defensive: every caller already latched before its first await, but set
    // it here too so a future caller of this method can't forget. Cleared on
    // both early returns below and in `_resetStreamState` once a stream ends.
    _turnInFlight = true;
    _markWarming();
    // Safety: a prompt that sexualizes a minor never reaches the model.
    final lastUser = historyMessages
        .where((m) => m.role == MessageRole.user)
        .lastOrNull;
    if (lastUser != null && SafetyGuard.blocks(lastUser.content)) {
      await _replyWithBlockedNotice(conversationId, parentMessageId);
      return;
    }
    await ensureModelLoaded();
    var current = state.value!;
    if (current.modelLoadError != null) {
      state = AsyncData(current.copyWith(clearWarmingSince: true));
      _keepAliveLink?.close();
      _keepAliveLink = null;
      _turnInFlight = false;
      return;
    }
    if (current.modelId == null) {
      state = AsyncData(
        current.copyWith(
          modelLoadError: const EngineLoadFailure(
            'no model selected for this conversation',
          ),
          clearWarmingSince: true,
        ),
      );
      _keepAliveLink?.close();
      _keepAliveLink = null;
      _turnInFlight = false;
      return;
    }

    if (!_holdsHealthLease) {
      _holdsHealthLease = ref
          .read(deviceHealthProvider.notifier)
          .startPollingIfEnabled();
    }
    state = AsyncData(
      current.copyWith(
        isGenerating: true,
        awaitingFirstToken: true,
        liveTokPerSec: 0,
        clearStreamingMessageId: true,
      ),
    );

    final MessageInfo? continued = continueMessageId == null
        ? null
        : current.messages.where((m) => m.id == continueMessageId).firstOrNull;
    final int assistantId;
    if (continued == null) {
      assistantId = await _repo.appendMessage(
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
    } else {
      assistantId = continued.id;
      current = state.value!;
      // Shown as a normal streaming bubble again (not the error card) while
      // the continuation runs; the terminal status is set on completion.
      state = AsyncData(
        current.copyWith(
          messages: [
            for (final m in current.messages)
              if (m.id == assistantId)
                m.copyWith(status: MessageStatus.complete)
              else
                m,
          ],
          streamingMessageId: assistantId,
        ),
      );
    }

    _activeAssistantId = assistantId;
    _continuing = continued != null;
    _seedRaw = continued == null ? '' : _seedFor(continued);
    _rawBuffer = '';
    _outputBlocked = false;
    _pushedContent = continued?.content ?? '';
    _pushedReasoning = continued?.reasoningContent ?? '';
    _reasoningStartedAt = null;
    _tokenArrivals.clear();

    // Guard: only forward images to the engine once THIS turn's own
    // ensureModelLoaded confirms isMultimodal — never based on stale state
    // from before the load (the composer's attach button being gated on
    // isMultimodal should already prevent this, but a stale in-flight image
    // from a just-swapped model must not reach a text-only engine).
    // Settings > About me: the short "About the user" block rides on the
    // system turn for Ask, Actions and character chats alike ('' when empty).
    final userContext = ref.read(userContextProvider).value ?? '';
    final turns = _historyTurns(
      continued == null
          ? historyMessages
          : [
              for (final m in historyMessages)
                // An errored partial reply is normally dropped from history;
                // a continuation needs it as the assistant turn to extend.
                if (m.id == continued.id)
                  m.copyWith(status: MessageStatus.complete)
                else
                  m,
            ],
      current.systemPrompt,
      current.isMultimodal ? current.attachedImages : const {},
      userContext: userContext,
    );
    if (continued != null) turns.add(const ChatTurn.user(_continuePrompt));
    final samplingParams = current.samplingParams;
    _activeSources = const [];
    try {
      // A continuation extends an already-grounded answer; never re-ground.
      final grounded = continued != null
          ? null
          : await _groundQuestion(
              conversationId: conversationId,
              historyMessages: historyMessages,
              systemPrompt: current.systemPrompt,
              samplingParams: samplingParams,
            );
      final pinnedPrompt = continued != null || grounded != null
          ? null
          : _groundInPinned(historyMessages);
      if (pinnedPrompt != null) {
        final last = turns.lastIndexWhere((t) => t.role == EngineRole.user);
        if (last >= 0) {
          turns[last] = ChatTurn.user(pinnedPrompt, images: turns[last].images);
        }
      }
      if (grounded != null) {
        // Swap the plain question for the grounded prompt, on this request
        // only: the stored message (and so the history shown/exported) keeps
        // the user's own words.
        final last = turns.lastIndexWhere((t) => t.role == EngineRole.user);
        if (last >= 0) {
          turns[last] = ChatTurn.user(
            grounded.prompt,
            images: turns[last].images,
          );
          _activeSources = grounded.sources;
        }
      }
    } catch (e) {
      // Never answer a document question ungrounded: fail the turn instead.
      _onError(e);
      return;
    }
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
                if (_outputBlocked) break;
                _rawBuffer += event.text;
                _tokenArrivals.add(DateTime.now());
              case EngineHistoryTrimmed():
                // A context-shift discarded older history mid-generation to
                // keep this reply going. Not surfaced in the UI yet — a
                // future loop can show a "history trimmed" notice using
                // event.tokensDropped; for now this just keeps the switch
                // exhaustive and the stream flowing.
                break;
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
    // D3: no first token within the timeout -> offer Stop / Try again.
    _firstTokenTimer?.cancel();
    _firstTokenTimer = Timer(ref.read(firstTokenTimeoutProvider), () {
      final cur = state.value;
      if (cur == null || _disposed || !cur.awaitingFirstToken) return;
      state = AsyncData(cur.copyWith(firstTokenTimedOut: true));
    });
    // A reading taken before the stream existed (or an unchanged "critical",
    // which the listener never re-reports) must still stop this reply.
    if (_holdsHealthLease) _stopIfTooHot(ref.read(deviceHealthProvider));
    await completer.future;
  }

  void _flush({required bool isFinal}) {
    final id = _activeAssistantId;
    if (id == null) return;
    var split = splitThinkContent(
      _seedRaw + safeThinkPrefix(_rawBuffer, isFinal: isFinal),
    );
    // Safety: stop a reply that sexualizes a minor mid-stream and replace
    // everything shown so far with the notice.
    if (!_outputBlocked &&
        (SafetyGuard.blocksOutput(split.content) ||
            SafetyGuard.blocksOutput(split.reasoning))) {
      _outputBlocked = true;
      unawaited(ref.read(engineServiceProvider).cancel());
      _seedRaw = '';
      _rawBuffer = SafetyGuard.blockedNotice;
      split = splitThinkContent(_rawBuffer);
    }

    if (_reasoningStartedAt == null &&
        !_continuing &&
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
    // A continuation already has text, so "first token" means any new token.
    final awaiting = _continuing
        ? _rawBuffer.isEmpty
        : split.content.isEmpty && split.reasoning.isEmpty;
    if (!awaiting) _firstTokenTimer?.cancel();
    state = AsyncData(
      current.copyWith(
        messages: updatedMessages,
        awaitingFirstToken: awaiting,
        clearWarmingSince: !awaiting,
        firstTokenTimedOut: awaiting ? null : false,
        liveTokPerSec: _tokenArrivals.length.toDouble(),
        reasoningDurationMs: closedDurationMs == null
            ? current.reasoningDurationMs
            : {...current.reasoningDurationMs, id: closedDurationMs},
      ),
    );
  }

  /// Appends the assistant-styled "can't help" reply for a blocked prompt
  /// and releases the turn latch: no model load, no generation.
  Future<void> _replyWithBlockedNotice(
    int conversationId,
    int? parentMessageId,
  ) async {
    final id = await _repo.appendMessage(
      conversationId: conversationId,
      role: MessageRole.assistant,
      content: SafetyGuard.blockedNotice,
      parentMessageId: parentMessageId,
    );
    final current = state.value;
    if (current != null) {
      state = AsyncData(
        current.copyWith(
          clearWarmingSince: true,
          messages: [
            ...current.messages,
            MessageInfo(
              id: id,
              conversationId: conversationId,
              role: MessageRole.assistant,
              content: SafetyGuard.blockedNotice,
              status: MessageStatus.complete,
              createdAt: DateTime.now(),
              parentMessageId: parentMessageId,
            ),
          ],
        ),
      );
    }
    _keepAliveLink?.close();
    _keepAliveLink = null;
    _turnInFlight = false;
  }

  /// Mirrors a persisted report (`ReportRepository.submit` already set the
  /// row's flag) into the in-memory list so the bubble collapses at once.
  void markReported(int messageId) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        messages: [
          for (final m in current.messages)
            if (m.id == messageId) m.copyWith(reported: true) else m,
        ],
      ),
    );
  }

  void _onCompletion(EngineCompletion event) {
    _flushTimer?.cancel();
    _flush(isFinal: true);
    final id = _activeAssistantId;
    if (id == null) return;
    final status = _outputBlocked
        ? MessageStatus.complete
        : switch (event.reason) {
            EngineStopReason.cancelled => MessageStatus.cancelled,
            EngineStopReason.maxTokens => MessageStatus.truncated,
            EngineStopReason.endOfSequence => MessageStatus.complete,
          };
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
    final answer = _pushedContent;
    final sources = _activeSources.isEmpty || answer.trim().isEmpty
        ? const <DocSource>[]
        : citedSources(answer, _activeSources);
    if (sources.isNotEmpty) unawaited(_repo.setSources(id, sources));
    final updatedMessages = [
      for (final m in current.messages)
        if (m.id == id)
          m.copyWith(
            status: status,
            tokCount: event.tokenCount,
            genMs: event.elapsedMs,
            sources: sources.isEmpty ? null : sources,
          )
        else
          m,
    ];
    state = AsyncData(
      current.copyWith(
        messages: updatedMessages,
        isGenerating: false,
        awaitingFirstToken: false,
        clearWarmingSince: true,
        firstTokenTimedOut: false,
        liveTokPerSec: 0,
        clearStreamingMessageId: true,
        heatStoppedMessageIds: _heatStoppedId == id
            ? {...current.heatStoppedMessageIds, id}
            : null,
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
            clearWarmingSince: true,
            firstTokenTimedOut: false,
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
            clearWarmingSince: true,
            firstTokenTimedOut: false,
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
    _activeSources = const [];
    _outputBlocked = false;
    _rawBuffer = '';
    _pushedContent = '';
    _pushedReasoning = '';
    _reasoningStartedAt = null;
    _tokenArrivals.clear();
    _genSub = null;
    _flushTimer = null;
    _firstTokenTimer?.cancel();
    _firstTokenTimer = null;
    _continuing = false;
    _seedRaw = '';
    _keepAliveLink?.close();
    _keepAliveLink = null;
    _heatStoppedId = null;
    _releaseHealthLease();
    _turnInFlight = false;
  }

  /// Stamps the start of this turn's warm-up (see
  /// [ChatThreadState.warmingSince]).
  void _markWarming() {
    final cur = state.value;
    if (cur == null) return;
    state = AsyncData(
      cur.copyWith(warmingSince: DateTime.now(), firstTokenTimedOut: false),
    );
  }

  /// Raw (tag-bearing) text of a reply so far, the base a continuation
  /// appends to.
  String _seedFor(MessageInfo m) {
    final reasoning = m.reasoningContent ?? '';
    if (reasoning.isEmpty) return m.content;
    return m.content.isEmpty
        ? '$thinkOpenTag$reasoning'
        : '$thinkOpenTag$reasoning$thinkCloseTag${m.content}';
  }

  void _stopIfTooHot(DeviceHealth health) {
    final id = _activeAssistantId;
    if (id == null || _heatStoppedId != null) return;
    if (DeviceGuardPolicy.thermalAction(health.thermal) == ThermalAction.stop) {
      _heatStoppedId = id;
      unawaited(cancel());
    }
  }

  void _releaseHealthLease() {
    if (!_holdsHealthLease) return;
    _holdsHealthLease = false;
    // Notifier may already be gone when the whole container is disposing.
    if (ref.mounted) ref.read(deviceHealthProvider.notifier).stopPolling();
  }

  /// Heat guard action: stop any in-flight reply (partial text is kept), then
  /// switch this conversation to [model] (the smallest installed one).
  Future<void> useLighterModel(InstalledModelInfo model) async {
    if (state.value?.isGenerating ?? false) await cancel();
    // ponytail: poll for the cancel to land; an event-driven wait needs a
    // completer threaded through _resetStreamState, not worth it for a tap.
    for (var i = 0; i < 100 && _turnInFlight; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await switchModel(model);
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

  /// [attachedImages]: Loop 7's session-only image map (see
  /// [ChatThreadState.attachedImages]) — a user turn whose message id has an
  /// entry gets that image attached to its [ChatTurn], the only way an image
  /// reaches the engine (`EngineService.generate`'s `ChatTurn.images`).
  List<ChatTurn> _historyTurns(
    List<MessageInfo> messages,
    String systemPrompt,
    Map<int, Uint8List> attachedImages, {
    String userContext = '',
  }) {
    // Safety instruction rides on the system turn (prepended to the
    // persona/system prompt, or emitted alone) for every path; the "About
    // the user" block (when the user filled it in) follows it.
    final system = [
      SafetyGuard.systemInstruction,
      if (userContext.isNotEmpty) userContext,
      if (systemPrompt.trim().isNotEmpty) systemPrompt,
    ].join('\n\n');
    // Growable: `_runAssistantTurn` swaps the last user turn for its
    // document-grounded version.
    return [
      ChatTurn.system(system),
      for (final m in messages)
        // Blocked prompts and their notices are dropped from model history.
        if (m.status != MessageStatus.error &&
            !(m.role == MessageRole.user && SafetyGuard.blocks(m.content)) &&
            !(m.role == MessageRole.assistant &&
                m.content == SafetyGuard.blockedNotice))
          switch (m.role) {
            MessageRole.user => ChatTurn.user(
              m.content,
              images: attachedImages[m.id] == null
                  ? const []
                  : [attachedImages[m.id]!],
            ),
            MessageRole.assistant => ChatTurn.assistant(m.content),
            MessageRole.system => ChatTurn.system(m.content),
          },
    ];
  }
}
