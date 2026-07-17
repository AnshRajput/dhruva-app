// D2: the listing tile renders the right trailing affordance for each
// download state — Download button → progress ring (+ cancel) → Installed
// (Chat + Delete). Drives it by overriding the controller with fixed state.

import 'package:dhruva/core/theme/app_theme.dart';
import 'package:dhruva/data/hf_api/models/hf_model_summary.dart';
import 'package:dhruva/data/hf_api/models/model_license_info.dart';
import 'package:dhruva/features/models_hub/state/listing_download_controller.dart';
import 'package:dhruva/features/models_hub/widgets/model_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _repoId = 'bartowski/Llama-3.2-1B-Instruct-GGUF';

const _model = HfModelSummary(
  id: _repoId,
  likes: 10,
  downloads: 2000,
  tags: [],
  pipelineTag: 'text-generation',
  license: ModelLicenseInfo(
    license: 'apache-2.0',
    gatedStatus: HfGatedStatus.none,
  ),
);

class _StubController extends ListingDownloadController {
  final Map<String, ListingModelState> initial;
  _StubController(this.initial);
  @override
  Future<Map<String, ListingModelState>> build() async => initial;
}

Future<void> _pump(WidgetTester tester, ListingModelState state) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        listingDownloadControllerProvider.overrideWith(
          () => _StubController({_repoId: state}),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ModelListTile(model: _model, onTap: () {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('notInstalled shows a Download button', (tester) async {
    await _pump(tester, const ListingModelState());
    expect(find.byTooltip('Download'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('downloading shows a progress ring and a cancel affordance', (
    tester,
  ) async {
    await _pump(
      tester,
      const ListingModelState(
        status: ListingModelStatus.downloading,
        progress: 0.5,
      ),
    );
    final ring = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(ring.value, closeTo(0.5, 0.001));
    // The ring shows the live percentage and taps-to-cancel.
    expect(find.text('50%'), findsOneWidget);
    expect(find.byTooltip('Tap to cancel'), findsOneWidget);
    expect(find.byTooltip('Download'), findsNothing);
  });

  testWidgets('installed shows Chat + Delete actions', (tester) async {
    await _pump(
      tester,
      const ListingModelState(
        status: ListingModelStatus.installed,
        installedId: 1,
      ),
    );
    expect(find.byTooltip('Chat'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsOneWidget);
  });

  testWidgets('a mobile-friendly (small) model shows the hint chip', (
    tester,
  ) async {
    await _pump(tester, const ListingModelState());
    expect(find.text('Mobile-friendly'), findsOneWidget);
  });

  // QA (Phase B attack #3): totalBytes-unknown (progress stays 0.0) must
  // render an INDETERMINATE ring, not a ring stuck at a visible 0%. Bounded
  // pump on purpose — an indeterminate CircularProgressIndicator animates
  // forever and pumpAndSettle would time out waiting for it to stop.
  testWidgets('downloading with progress 0.0 (unknown total) renders an '
      'indeterminate ring', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          listingDownloadControllerProvider.overrideWith(
            () => _StubController({
              _repoId: const ListingModelState(
                status: ListingModelStatus.downloading,
                progress: 0.0,
              ),
            }),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: ModelListTile(model: _model, onTap: () {}),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final ring = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(ring.value, isNull);
  });

  // QA (Phase B attack #1): the "resolving" window (license+file-tree fetch
  // in flight, before a taskId exists) also renders an indeterminate ring —
  // same bounded-pump reasoning as above.
  testWidgets('resolving shows an indeterminate ring', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          listingDownloadControllerProvider.overrideWith(
            () => _StubController({
              _repoId: const ListingModelState(
                status: ListingModelStatus.resolving,
              ),
            }),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: ModelListTile(model: _model, onTap: () {}),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  // QA (Phase B attack #2), NOW FIXED: the installed row's Chat action follows
  // the app's OWN established pattern for "start a chat with a specific model"
  // — `context.push('/chat/new', extra: <drift row id>)`, which app_router's
  // `/chat/:id` builder reads as `ChatRouteArgs.initialModelId`. Tapping Chat
  // must carry the installed model so a LOADED conversation opens, not the
  // bare conversation list.
  testWidgets(
    'installed row Chat action opens /chat/new carrying the model id',
    (tester) async {
      String? visitedPath;
      Object? visitedExtra;
      final router = GoRouter(
        initialLocation: '/list',
        routes: [
          GoRoute(
            path: '/list',
            builder: (context, state) => Scaffold(
              body: ModelListTile(model: _model, onTap: () {}),
            ),
          ),
          GoRoute(
            path: '/chat/new',
            builder: (context, state) {
              visitedPath = state.uri.toString();
              visitedExtra = state.extra;
              return const Text('chat-thread');
            },
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            listingDownloadControllerProvider.overrideWith(
              () => _StubController({
                _repoId: const ListingModelState(
                  status: ListingModelStatus.installed,
                  installedId: 7,
                ),
              }),
            ),
          ],
          child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Chat'));
      await tester.pumpAndSettle();

      expect(find.text('chat-thread'), findsOneWidget);
      expect(visitedPath, '/chat/new');
      expect(
        visitedExtra,
        7,
        reason:
            'the installed model drift id must be carried as `extra` so the '
            'thread opens with that model preselected and loaded.',
      );
    },
  );
}
