/// go_router setup. `/today` is the app home (daily-assistant redesign). The
/// shell has four branches: Today, Inbox (tab hidden until an inbox source
/// exists), Ask (the old Chat tab) and Library. EVERYTHING else is a
/// full-screen route outside the shell: Settings (opened from Today's gear),
/// Actions (the old Workflows), Personas (the old Characters), the Models hub
/// (now under Settings), Compare/AI news (the old Playground), chat threads.
///
/// Rule for callers: screens outside the shell must never `push` a
/// shell-branch route (`/today`, `/inbox`, `/ask`, `/library`): that builds a
/// second shell whose branch renders blank (the 0.6.0 bug: chat -> mic ->
/// empty page). Use `go` to return to the shell, or push the full-screen
/// equivalent (`/models/hub`, `/inbox/connect`). `test/core/router` sweeps
/// `lib/` for violations.
///
/// Old routes keep working through [legacyRouteRedirect]: `/chat`,
/// `/characters`, `/models`, `/playground`, `/workflows` redirect to their new
/// homes (query strings preserved); `/chat/:id` is unchanged.
///
/// Repo ids contain a `/` (`namespace/model-name`), so callers must
/// percent-encode the id when pushing `/models/repo/:id` — `GoRoute`'s
/// `:id` only matches one path segment, and an encoded slash (`%2F`) stays
/// inside that segment.
library;

import 'package:go_router/go_router.dart';

import '../../features/characters/ui/character_detail_screen.dart';
import '../../features/characters/ui/character_form_screen.dart';
import '../../features/characters/ui/characters_gallery_screen.dart';
import '../../features/chat/state/chat_controller.dart';
import '../../features/chat/ui/chat_thread_screen.dart';
import '../../features/chat/ui/conversation_list_screen.dart';
import '../../features/inbox/ui/inbox_item_screen.dart';
import '../../features/inbox/ui/inbox_screen.dart';
import '../../features/library/ui/file_search_screen.dart';
import '../../features/library/ui/library_lists_screen.dart';
import '../../features/library/ui/library_screen.dart';
import '../../features/models_hub/ui/advanced_search_screen.dart';
import '../../features/models_hub/ui/downloads_screen.dart';
import '../../features/models_hub/ui/model_detail_screen.dart';
import '../../features/models_hub/ui/models_hub_screen.dart';
import '../../features/models_hub/widgets/download_status_pill.dart';
import '../../features/onboarding/ui/onboarding_screen.dart';
import '../../features/playground/ui/playground_screen.dart';
import '../../features/settings/state/feedback_controller.dart';
import '../../features/settings/ui/about_me_screen.dart';
import '../../features/settings/ui/about_screen.dart';
import '../../features/settings/ui/connectors_screen.dart';
import '../../features/settings/ui/crash_reports_screen.dart';
import '../../features/settings/ui/feedback_screen.dart';
import '../../features/settings/ui/ledger_screen.dart';
import '../../features/settings/ui/notifications_screen.dart';
import '../../features/settings/ui/privacy_screen.dart';
import '../../features/settings/ui/safety_screen.dart';
import '../../features/settings/ui/settings_screen.dart';
import '../../features/today/ui/day_timeline_screen.dart';
import '../../features/today/ui/prep_screen.dart';
import '../../features/today/ui/today_screen.dart';
import '../../features/voice/ui/handsfree_screen.dart';
import '../../features/workflows/ui/workflows_screen.dart';
import 'app_shell.dart';
import 'ask_route.dart';

/// Maps a pre-redesign route to its new home, or null if [uri] is current.
/// Pure so tests can pin every old route. Query strings are preserved
/// (`/models?tab=voice`, `/workflows?text=...`).
String? legacyRouteRedirect(Uri uri) {
  final path = uri.path.length > 1 && uri.path.endsWith('/')
      ? uri.path.substring(0, uri.path.length - 1)
      : uri.path;
  final query = uri.hasQuery ? '?${uri.query}' : '';
  return switch (path) {
    '/' => '/today',
    '/chat' => '/ask',
    '/characters' => '/personas',
    '/models' => '/settings/models$query',
    '/playground' => '/settings/models/compare$query',
    '/workflows' => '/actions$query',
    _ => null,
  };
}

/// Locations that are shell branches. Navigating to one from outside the
/// shell must use `go`, never `push` (see the library doc).
bool isShellLocation(String location) {
  final path = Uri.parse(location).path;
  return const {'/today', '/inbox', '/ask', '/library'}.contains(path);
}

final appRouter = GoRouter(
  initialLocation: '/today',
  redirect: (context, state) => legacyRouteRedirect(state.uri),
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/today',
              builder: (context, state) =>
                  const TodayScreen(statusPill: DownloadStatusPill()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/inbox',
              builder: (context, state) => const InboxScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/ask',
              builder: (context, state) => const ConversationListScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/library',
              builder: (context, state) => const LibraryScreen(),
            ),
          ],
        ),
      ],
    ),
    // Library sub-pages (full-screen, outside the shell): file search and the
    // "See all" lists.
    GoRoute(
      path: '/library/search',
      builder: (context, state) => const FileSearchScreen(),
    ),
    GoRoute(
      path: '/library/documents',
      builder: (context, state) => const DocumentsScreen(),
    ),
    GoRoute(
      path: '/library/saved',
      builder: (context, state) => const SavedScreen(),
    ),
    // Settings opens full-screen from the gear on Today.
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/settings/connectors',
      builder: (context, state) => const ConnectorsScreen(),
    ),
    GoRoute(
      path: '/settings/connectors/ledger',
      builder: (context, state) => const LedgerScreen(),
    ),
    GoRoute(
      path: '/settings/about-me',
      builder: (context, state) => const AboutMeScreen(),
    ),
    GoRoute(
      path: '/settings/notifications',
      builder: (context, state) => const NotificationsScreen(),
    ),
    GoRoute(
      path: '/settings/privacy',
      builder: (context, state) => const PrivacyScreen(),
    ),
    // Models hub now lives under Settings (full-screen). `/models` redirects
    // here; `/models/hub` stays as the alias out-of-shell callers push.
    GoRoute(
      path: '/settings/models',
      builder: (context, state) => _modelsHub(state),
    ),
    // Compare two models + AI news (the old Playground tab). `?tab=news`
    // opens AI news.
    GoRoute(
      path: '/settings/models/compare',
      builder: (context, state) => PlaygroundScreen(
        initialTabIndex: state.uri.queryParameters['tab'] == 'news' ? 1 : 0,
      ),
    ),
    // "Set up your inbox" from Today: the Inbox connect state as a full-screen
    // route, so Today never pushes the shell's own /inbox branch.
    GoRoute(
      path: '/inbox/connect',
      builder: (context, state) => const InboxScreen(standalone: true),
    ),
    // One notification in full (opened from an Inbox row).
    GoRoute(
      path: '/inbox/item/:id',
      builder: (context, state) {
        final id = int.tryParse(state.pathParameters['id']!);
        return id == null
            ? const InboxScreen(standalone: true)
            : InboxItemScreen(itemId: id);
      },
    ),
    // Rule-built meeting prep (no model): `/prep/<event item id>`.
    GoRoute(
      path: '/prep/:id',
      builder: (context, state) =>
          PrepScreen(eventId: int.tryParse(state.pathParameters['id']!) ?? 0),
    ),
    GoRoute(
      path: '/day',
      builder: (context, state) => const DayTimelineScreen(),
    ),
    // Personas (the old Characters gallery), reached from Ask.
    GoRoute(
      path: '/personas',
      builder: (context, state) => const CharactersGalleryScreen(),
    ),
    // A fresh Ask thread, optionally prefilled and with sources pinned:
    // `/ask/new?q=Prep me for Budget review&sources=calendar,contacts,files`
    // (contract + builder in `ask_route.dart`). Outside the shell, so callers
    // `push` it. `extra` may carry an installed model id, like `/chat/new`.
    GoRoute(
      path: '/ask/new',
      builder: (context, state) {
        final q = parseAskNewQuery(
          state.uri.queryParameters,
          focus: state.uri.queryParametersAll['focus'] ?? const [],
        );
        return ChatThreadScreen(
          args: ChatRouteArgs(
            initialModelId: state.extra is int ? state.extra! as int : null,
            initialDraft: q.draft,
            initialSources: q.sources,
            focusItemIds: q.focus,
            about: q.about,
          ),
        );
      },
    ),
    GoRoute(
      path: '/chat/:id',
      builder: (context, state) {
        final idParam = state.pathParameters['id']!;
        // QA BUG-4: a malformed, non-numeric id (stale/hand-typed link,
        // external share intent) used to hit `int.parse` unguarded and
        // throw a FormatException straight out of the route builder — an
        // uncaught, uncatchable-by-the-app red screen. `tryParse` folds
        // that case into the same draft-conversation path `idParam ==
        // 'new'` already takes, which is exactly the graceful fallback the
        // nonexistent-numeric-id case gets too (no model set -> the
        // thread screen's own "No model installed yet" empty state).
        final conversationId = idParam == 'new' ? null : int.tryParse(idParam);
        if (conversationId == null) {
          // Loop 5: a character's "Chat with {name}" CTA pushes
          // `/chat/new?characterId=<id>` — a query param rather than
          // `extra` — so `features/characters` never has to import
          // `ChatRouteArgs` from `features/chat` (ADR-002 bans
          // cross-feature imports; only this composition root reaches into
          // feature code directly, per `app_shell.dart`'s own doc). The
          // existing `extra: modelId` (an `int`) call site — the
          // conversation-list screen's model-picker flow — is untouched.
          final characterIdParam = state.uri.queryParameters['characterId'];
          // WS2: onboarding's "Try asking" chips push
          // `/chat/new?prompt=<encoded>` (extra: installed model id) so the
          // first turn auto-sends — a query param, like `characterId`, so
          // `features/onboarding` never imports `ChatRouteArgs` (ADR-002).
          final promptParam = state.uri.queryParameters['prompt'];
          // Actions: the instruction rides in the system prompt (`asys`), the
          // user's text is `prompt`; `pkg` / `app` name the message's source
          // app so a drafted reply can offer "Open in <app>".
          final actionSystem = state.uri.queryParameters['asys'];
          // Android widget "Talk" (IntentInbox route `talk`): open hands-free
          // voice as soon as the new chat is ready.
          final openVoice = state.uri.queryParameters['talk'] == '1';
          return ChatThreadScreen(
            openVoiceOnStart: openVoice,
            args: ChatRouteArgs(
              initialModelId: state.extra as int?,
              characterId: characterIdParam == null
                  ? null
                  : int.tryParse(characterIdParam),
              initialPrompt: promptParam,
              actionSystemPrompt: actionSystem,
              sourcePackage: state.uri.queryParameters['pkg'],
              sourceApp: state.uri.queryParameters['app'],
            ),
          );
        }
        return ChatThreadScreen(
          args: ChatRouteArgs(conversationId: conversationId),
        );
      },
    ),
    // Actions (the old Workflows): `?text=` prefills the input (share sheet /
    // text-selection intents via `IntentInbox`), `?id=` opens one action's
    // sheet directly (Ask quick strip, Today quick actions) — query params so
    // `features/chat` / `features/today` never import `features/workflows`
    // (ADR-002). `/workflows` redirects here.
    GoRoute(
      path: '/actions',
      builder: (context, state) => WorkflowsScreen(
        initialText: state.uri.queryParameters['text'],
        initialWorkflowId: state.uri.queryParameters['id'],
        sourcePackage: state.uri.queryParameters['pkg'],
        sourceApp: state.uri.queryParameters['app'],
      ),
    ),
    GoRoute(
      path: '/characters/new',
      builder: (context, state) => const CharacterFormScreen(),
    ),
    GoRoute(
      path: '/characters/:id',
      builder: (context, state) {
        final id = int.tryParse(state.pathParameters['id']!);
        if (id == null) return const CharactersGalleryScreen();
        return CharacterDetailScreen(characterId: id);
      },
    ),
    GoRoute(
      path: '/characters/:id/edit',
      builder: (context, state) {
        final id = int.tryParse(state.pathParameters['id']!);
        if (id == null) return const CharactersGalleryScreen();
        return CharacterFormScreen(characterId: id);
      },
    ),
    // WS2: the guided first-run flow. NOT the router's `initialLocation`
    // (that stays `/today`) —
    // `main()` reads the "onboarding done" flag ONCE at startup and, only on
    // a fresh install, redirects here before the first frame. Onboarding
    // writes the flag on finish/skip and `context.go('/today')`, so it's a
    // one-time cold-start decision, not an always-on redirect.
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: '/models/repo/:id',
      builder: (context, state) {
        final encoded = state.pathParameters['id']!;
        return ModelDetailScreen(repoId: Uri.decodeComponent(encoded));
      },
    ),
    // Full-screen Models hub for screens OUTSIDE the tab shell (chat thread,
    // hands-free, model picker). Pushing the shell's own `/models` from there
    // builds a second shell whose Models branch renders blank (0.6.0 bug:
    // chat → mic → empty page). Push this instead; back returns to the caller.
    GoRoute(
      path: '/models/hub',
      builder: (context, state) => _modelsHub(state),
    ),
    GoRoute(
      path: '/models/search',
      builder: (context, state) => const AdvancedSearchScreen(),
    ),
    GoRoute(
      path: '/models/downloads',
      builder: (context, state) => const DownloadsScreen(),
    ),
    GoRoute(
      path: '/settings/safety',
      builder: (context, state) => const SafetyScreen(),
    ),
    GoRoute(
      path: '/settings/crash-reports',
      builder: (context, state) => const CrashReportsScreen(),
    ),
    // `?type=bug|feature`; `&crash=1` (from the crash banner) ticks the crash log.
    GoRoute(
      path: '/settings/feedback',
      builder: (context, state) => FeedbackScreen(
        entry: feedbackEntryFromQuery(state.uri.queryParameters),
      ),
    ),
    GoRoute(
      path: '/settings/about',
      builder: (context, state) => const AboutScreen(),
    ),
    // Loop 6, T2/D3: `HandsFreeScreen` (`features/voice`) never imports
    // `features/chat` (ADR-002) — `ChatThreadScreen._openHandsFree` builds
    // the "say this, get the reply" closure against its own
    // `ChatController` and passes it as `extra`; this route is the one
    // place both features meet, same composition-root role this file's own
    // doc comment already claims for the character-chat query-param wiring
    // above.
    GoRoute(
      path: '/voice/handsfree',
      builder: (context, state) => HandsFreeScreen(
        onUserUtterance: state.extra! as Future<String?> Function(String),
      ),
    ),
  ],
);

/// `?tab=voice` opens straight on the Voice tab.
ModelsHubScreen _modelsHub(GoRouterState state) => ModelsHubScreen(
  initialTabIndex: state.uri.queryParameters['tab'] == 'voice' ? 2 : 0,
);
