/// go_router setup. `/chat` is the app home (chat-spec.md §1: "the product's
/// make-or-break feature and the MVP closer" — Loop 4). Characters (Loop 5),
/// models hub, and settings are the second/third/fourth bottom-nav
/// destinations (`app_shell.dart`).
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
import '../../features/models_hub/ui/advanced_search_screen.dart';
import '../../features/models_hub/ui/downloads_screen.dart';
import '../../features/models_hub/ui/model_detail_screen.dart';
import '../../features/models_hub/ui/models_hub_screen.dart';
import '../../features/onboarding/ui/onboarding_screen.dart';
import '../../features/playground/ui/playground_screen.dart';
import '../../features/settings/ui/about_screen.dart';
import '../../features/settings/ui/settings_screen.dart';
import '../../features/voice/ui/handsfree_screen.dart';
import 'app_shell.dart';

final appRouter = GoRouter(
  initialLocation: '/chat',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/chat',
              builder: (context, state) => const ConversationListScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/characters',
              builder: (context, state) => const CharactersGalleryScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/models',
              builder: (context, state) => const ModelsHubScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/playground',
              builder: (context, state) => const PlaygroundScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
      ],
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
          return ChatThreadScreen(
            args: ChatRouteArgs(
              initialModelId: state.extra as int?,
              characterId: characterIdParam == null
                  ? null
                  : int.tryParse(characterIdParam),
            ),
          );
        }
        return ChatThreadScreen(
          args: ChatRouteArgs(conversationId: conversationId),
        );
      },
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
    // (that stays `/chat` so every existing deep-link/test lands on chat) —
    // `main()` reads the "onboarding done" flag ONCE at startup and, only on
    // a fresh install, redirects here before the first frame. Onboarding
    // writes the flag on finish/skip and `context.go('/chat')`, so it's a
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
    GoRoute(
      path: '/models/search',
      builder: (context, state) => const AdvancedSearchScreen(),
    ),
    GoRoute(
      path: '/models/downloads',
      builder: (context, state) => const DownloadsScreen(),
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
