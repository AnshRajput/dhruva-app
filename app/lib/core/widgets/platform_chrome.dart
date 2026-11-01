/// Platform-adaptive CHROME (CLAUDE.md Rule 6): the bottom tab bar and top app
/// bar. Content is never skinned; only the interactive chrome layer adapts.
///
/// - Android: Material 3 Expressive. Pill nav indicator, stadium shapes, all
///   from the theme (`AppTheme`, radius token `full`). Chrome here is plain
///   solid surfaces.
/// - iOS: Cupertino-feel chrome with a translucent bar.
///
/// IMPORTANT, honest naming: the iOS translucent bars are an APPROXIMATION of
/// Apple's Liquid Glass (iOS 26). Flutter has no first-party API for the real
/// material, so this is a `BackdropFilter` blur over a translucent fill with a
/// hairline light edge. It does not refract, shift highlights with device
/// motion, or morph. It is applied to chrome only (never cards or content), as
/// ONE layer (never glass on glass), and falls back to a solid surface when
/// "reduce transparency" applies. Swap [GlassChrome] for a native platform
/// view if a real Liquid Glass bridge is ever justified.
///
/// Reduce-transparency fallback: Flutter exposes no iOS "Reduce Transparency"
/// flag, so we honour `MediaQuery.highContrast` (iOS "Increase Contrast") plus
/// the explicit in-app switch (Settings > Appearance,
/// `reduceTransparencyProvider`).
///
/// Branching is on `Theme.of(context).platform`, never `dart:io Platform`.
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/appearance_providers.dart';

/// True when the platform wants Cupertino-feel chrome.
bool isCupertinoChrome(BuildContext context) =>
    Theme.of(context).platform == TargetPlatform.iOS;

/// Whether chrome should render as translucent glass (approximation).
/// Pure function so tests can pin each input.
bool shouldUseGlass({
  required TargetPlatform platform,
  required bool highContrast,
  required bool reduceTransparencySetting,
}) =>
    platform == TargetPlatform.iOS &&
    !highContrast &&
    !reduceTransparencySetting;

bool useGlassChrome(BuildContext context, WidgetRef ref) => shouldUseGlass(
  platform: Theme.of(context).platform,
  highContrast: MediaQuery.highContrastOf(context),
  reduceTransparencySetting:
      ref.watch(reduceTransparencyProvider).value ?? false,
);

/// A bar surface. Translucent (blur + fill + hairline) when [glass], solid
/// otherwise. [edge] is the side that touches content: the hairline goes there.
class GlassChrome extends StatelessWidget {
  const GlassChrome({
    super.key,
    required this.glass,
    required this.edge,
    required this.child,
  });

  final bool glass;
  final Widget child;

  /// `top` for a bottom tab bar, `bottom` for an app bar.
  final GlassEdge edge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hairline = BorderSide(
      color: scheme.onSurface.withValues(alpha: glass ? 0.10 : 0.08),
      width: 0.5,
    );
    final border = switch (edge) {
      GlassEdge.top => Border(top: hairline),
      GlassEdge.bottom => Border(bottom: hairline),
    };
    if (!glass) {
      return DecoratedBox(
        decoration: BoxDecoration(color: scheme.surface, border: border),
        child: child,
      );
    }
    return ClipRect(
      child: BackdropFilter(
        // Blur stays modest (cost scales with radius; keep under 20-30).
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.72),
            border: border,
          ),
          child: child,
        ),
      ),
    );
  }
}

enum GlassEdge { top, bottom }

/// Bottom tab bar chrome. Wrap a `NavigationBar` in this; on iOS the bar
/// loses its pill indicator (Cupertino tab bars tint the icon instead) and
/// goes transparent so the glass layer shows through.
class AdaptiveTabBar extends ConsumerWidget {
  const AdaptiveTabBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<NavigationDestination> destinations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cupertino = isCupertinoChrome(context);
    final glass = useGlassChrome(context, ref);
    final theme = Theme.of(context);
    final bar = NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      destinations: destinations,
      backgroundColor: cupertino ? Colors.transparent : null,
      indicatorColor: cupertino ? Colors.transparent : null,
    );
    if (!cupertino) return bar;
    return GlassChrome(
      glass: glass,
      edge: GlassEdge.top,
      child: Theme(
        // Cupertino-feel: selected = primary tint, no pill.
        data: theme.copyWith(
          navigationBarTheme: theme.navigationBarTheme.copyWith(
            iconTheme: WidgetStateProperty.resolveWith(
              (states) => IconThemeData(
                color: states.contains(WidgetState.selected)
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        child: bar,
      ),
    );
  }
}

/// App bar for the new surfaces (Today, Inbox, Library). On iOS glass it is a
/// translucent bar; pair it with [ChromeScaffold], which lets content scroll
/// underneath.
class AdaptiveAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const AdaptiveAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
  });

  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glass = useGlassChrome(context, ref);
    return AppBar(
      title: title,
      actions: actions,
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
      backgroundColor: glass ? Colors.transparent : null,
      scrolledUnderElevation: 0,
      flexibleSpace: glass
          ? const GlassChrome(
              glass: true,
              edge: GlassEdge.bottom,
              child: SizedBox.expand(),
            )
          : null,
    );
  }
}

/// Scaffold for the new tab surfaces: on iOS glass the body runs behind the
/// app bar (and the shell's tab bar) so content scrolls under the translucent
/// chrome.
///
/// The body is a builder because a scrollable that sets its own `padding`
/// drops the Scaffold's MediaQuery inset, which would park the first row under
/// the glass bar. [bodyBuilder] hands over that inset (top = app bar, bottom =
/// tab bar; zero when the chrome is solid and already outside the body) to add
/// to the list's own padding.
class ChromeScaffold extends ConsumerWidget {
  const ChromeScaffold({
    super.key,
    required this.appBar,
    required this.bodyBuilder,
    this.floatingActionButton,
  });

  final AdaptiveAppBar appBar;
  final Widget Function(BuildContext context, EdgeInsets inset) bodyBuilder;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glass = useGlassChrome(context, ref);
    return Scaffold(
      extendBodyBehindAppBar: glass,
      appBar: appBar,
      body: Builder(
        builder: (context) {
          final p = MediaQuery.paddingOf(context);
          return bodyBuilder(
            context,
            EdgeInsets.only(top: p.top, bottom: p.bottom),
          );
        },
      ),
      floatingActionButton: floatingActionButton,
    );
  }
}
