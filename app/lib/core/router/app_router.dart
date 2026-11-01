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
import '../../features/inbox/ui/inbox_screen.dart';
import '../../features/library/ui/library_screen.dart';
import '../../features/models_hub/ui/advanced_search_screen.dart';
import '../../features/models_hub/ui/downloads_screen.dart';
import '../../features/models_hub/ui/model_detail_screen.dart';
import '../../features/models_hub/ui/models_hub_screen.dart';
import '../../features/models_hub/widgets/download_status_pill.dart';
import '../../features/onboarding/ui/onboarding_screen.dart';
import '../../features/playground/ui/playground_screen.dart';
import '../../features/settings/ui/about_screen.dart';
import '../../features/settings/ui/connectors_screen.dart';
import '../../features/settings/ui/crash_reports_screen.dart';
import '../../features/settings/ui/safety_screen.dart';
import '../../features/settings/ui/settings_screen.dart';
import '../../features/today/ui/day_timeline_screen.dart';
import '../../features/today/ui/today_screen.dart';
import '../../features/voice/ui/handsfree_screen.dart';
import '../../features/workflows/ui/workflows_screen.dart';
import 'app_shell.dart';

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
    // Settings opens full-screen from the gear on Today.
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/settings/connectors',
      builder: (context, state) => const ConnectorsScreen(),
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
    GoRoute(
      path: '/day',
      builder: (context, state) => const DayTimelineScreen(),
    ),
    // Personas (the old Characters gallery), reached from Ask.
    GoRoute(
      path: '/personas',
      builder: (context, state) => const CharactersGalleryScreen(),
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
