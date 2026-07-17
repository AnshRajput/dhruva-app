/// go_router setup (T5). `/models` is the app home. Repo ids contain a `/`
/// (`namespace/model-name`), so callers must percent-encode the id when
/// pushing `/models/repo/:id` — `GoRoute`'s `:id` only matches one path
/// segment, and an encoded slash (`%2F`) stays inside that segment.
library;

import 'package:go_router/go_router.dart';

import '../../features/debug_chat/debug_chat_screen.dart';
import '../../features/models_hub/ui/downloads_screen.dart';
import '../../features/models_hub/ui/model_detail_screen.dart';
import '../../features/models_hub/ui/models_hub_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/models',
  routes: [
    GoRoute(
      path: '/models',
      builder: (context, state) => const ModelsHubScreen(),
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
    GoRoute(
      path: '/debug-chat',
      builder: (context, state) => const DebugChatScreen(),
    ),
  ],
);
