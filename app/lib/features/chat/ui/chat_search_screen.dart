/// Search across every chat (titles + message content). Pushed from the
/// conversation list's app-bar search action; kept in its own file so the
/// list screen only carries the one-line entry point.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/brand_star.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../core/widgets/failure_view.dart';
import '../state/chat_search_provider.dart';

/// App-bar action that opens [ChatSearchScreen].
class ChatSearchAction extends StatelessWidget {
  const ChatSearchAction({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.search),
      tooltip: 'Search chats',
      onPressed: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const ChatSearchScreen())),
    );
  }
}

class ChatSearchScreen extends ConsumerStatefulWidget {
  const ChatSearchScreen({super.key});

  @override
  ConsumerState<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends ConsumerState<ChatSearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search chats',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            suffixIcon: IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Clear',
              onPressed: () {
                _ctrl.clear();
                _debounce?.cancel();
                setState(() => _query = '');
              },
            ),
          ),
        ),
      ),
      body: _query.isEmpty
          ? const SizedBox.shrink()
          : switch (ref.watch(chatSearchProvider(_query))) {
              AsyncData(:final value) when value.isEmpty => Center(
                child: Text(
                  'No chats match',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              AsyncData(:final value) => ListView.builder(
                itemCount: value.length,
                itemBuilder: (context, i) {
                  final hit = value[i];
                  return ListTile(
                    title: Text(
                      hit.title.isEmpty ? 'Untitled conversation' : hit.title,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Title-only match: the snippet is the title again — skip it.
                    subtitle: hit.snippet == hit.title
                        ? null
                        : Text(
                            hit.snippet,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: tokens.spacing.md,
                    ),
                    onTap: () => context.push('/chat/${hit.conversationId}'),
                  );
                },
              ),
              AsyncError(:final error) => ErrorStateView(
                error: error,
                onRetry: () => ref.invalidate(chatSearchProvider(_query)),
              ),
              _ => const Center(child: DhruvaLoader()),
            },
    );
  }
}
