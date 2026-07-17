/// go_router setup. `/chat` is the app home (chat-spec.md §1: "the product's
/// make-or-break feature and the MVP closer" — Loop 4). Models hub moved to
/// the second bottom-nav destination (`app_shell.dart`) alongside it.
///
/// Repo ids contain a `/` (`namespace/model-name`), so callers must
/// percent-encode the id when pushing `/models/repo/:id` — `GoRoute`'s
/// `:id` only matches one path segment, and an encoded slash (`%2F`) stays
/// inside that segment.
library;

import 'package:go_router/go_router.dart';

import '../../features/chat/state/chat_controller.dart';
import '../../features/chat/ui/chat_thread_screen.dart';
import '../../features/chat/ui/conversation_list_screen.dart';
import '../../features/models_hub/ui/downloads_screen.dart';
import '../../features/models_hub/ui/model_detail_screen.dart';
import '../../features/models_hub/ui/models_hub_screen.dart';
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
              path: '/models',
              builder: (context, state) => const ModelsHubScreen(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/chat/:id',
      builder: (context, state) {
        final idParam = state.pathParameters['id']!;
        if (idParam == 'new') {
          return ChatThreadScreen(
            args: ChatRouteArgs(initialModelId: state.extra as int?),
          );
        }
        return ChatThreadScreen(
          args: ChatRouteArgs(conversationId: int.parse(idParam)),
        );
      },
    ),
    GoRoute(
      path: '/models/repo/:id',
      builder: (context, state) {
        final encoded = state.pathParameters['id']!;
        return ModelDetailScreen(repoId: Uri.decodeComponent(encoded));
      },
    ),
    GoRoute(
      path: '/models/downloads',
      builder: (context, state) => const DownloadsScreen(),
    ),
  ],
);
