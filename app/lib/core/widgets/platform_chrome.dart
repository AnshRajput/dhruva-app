/// Platform-adaptive CHROME (CLAUDE.md Rule 6): the bottom tab bar and top app
/// bar. Content is never skinned; only the interactive chrome layer adapts.
///
/// - Android: Material 3 Expressive. Pill nav indicator, stadium shapes, all
///   from the theme (`AppTheme`, radius token `full`). Chrome here is plain
///   solid surfaces.
/// - iOS: Cupertino-feel chrome: a floating pill tab bar with a selected-tab
///   pill (`comps/today-ios.png`) and an app bar that turns translucent once
///   content scrolls under it.
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

import '../theme/app_theme.dart' show overlayStyleFor;
import '../theme/appearance_providers.dart';
import '../theme/design_tokens.dart';
import '../theme/dhruva_theme_extension.dart';
import 'pressable_scale.dart';

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

/// Bottom tab bar chrome. Android: the Material 3 `NavigationBar` with its
/// pill indicator (from the theme). iOS: a FLOATING PILL (inset from the screen
/// edges, fully rounded) with a selected-tab pill, per `comps/today-ios.png`.
/// The pill is the one translucent layer (an approximation, see the library
/// header); under reduce-transparency / increase-contrast it is a solid
/// surface with a hairline.
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
    if (!isCupertinoChrome(context)) {
      return NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelected,
        destinations: destinations,
      );
    }
    return _FloatingPillTabBar(
      glass: useGlassChrome(context, ref),
      selectedIndex: selectedIndex,
      onSelected: onSelected,
      destinations: destinations,
    );
  }
}

class _FloatingPillTabBar extends StatelessWidget {
  const _FloatingPillTabBar({
    required this.glass,
    required this.selectedIndex,
    required this.onSelected,
    required this.destinations,
  });

  final bool glass;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<NavigationDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = theme.extension<DhruvaTokens>()!;
    final radius = BorderRadius.circular(tokens.radius.full);
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: glass ? 0.72 : 1),
        borderRadius: radius,
        border: Border.all(
          color: scheme.onSurface.withValues(alpha: glass ? 0.12 : 0.10),
          width: 0.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            for (var i = 0; i < destinations.length; i++)
              Expanded(
                child: _PillTab(
                  destination: destinations[i],
                  selected: i == selectedIndex,
                  onTap: () => onSelected(i),
                ),
              ),
          ],
        ),
      ),
    );
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DecoratedBox(
          // Soft lift so the pill reads as floating; it sits outside the clip.
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: 0.16),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: glass
                ? BackdropFilter(
                    // Modest blur (cost scales with radius).
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: surface,
                  )
                : surface,
          ),
        ),
      ),
    );
  }
}

class _PillTab extends StatelessWidget {
  const _PillTab({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final NavigationDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = theme.extension<DhruvaTokens>()!;
    final fg = selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return Semantics(
      selected: selected,
      container: true,
      button: true,
      label: destination.label,
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : tokens.motion.fast,
          curve: TokenMotionCurve.decelerate,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(tokens.radius.full),
          ),
          child: IconTheme(
            data: IconThemeData(color: fg, size: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected)
                  destination.selectedIcon ?? destination.icon
                else
                  destination.icon,
                const SizedBox(height: 2),
                Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: fg,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// App bar for the new surfaces (Today, Inbox, Library). On iOS it is clear at
/// rest and fades to translucent glass once content scrolls under it; pair it
/// with [ChromeScaffold], which lets content scroll underneath.
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
      // Explicit: a transparent bar would otherwise be judged "dark" and force
      // white clock/battery on the light theme.
      systemOverlayStyle: overlayStyleFor(Theme.of(context).brightness),
      flexibleSpace: glass ? const _ScrollGlass() : null,
    );
  }
}

/// Glass that fades in only while content is scrolled under the bar.
class _ScrollGlass extends StatefulWidget {
  const _ScrollGlass();

  @override
  State<_ScrollGlass> createState() => _ScrollGlassState();
}

class _ScrollGlassState extends State<_ScrollGlass> {
  ScrollNotificationObserverState? _observer;
  bool _scrolled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _observer?.removeListener(_onScroll);
    _observer = ScrollNotificationObserver.maybeOf(context)
      ?..addListener(_onScroll);
  }

  @override
  void dispose() {
    _observer?.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll(ScrollNotification n) {
    // Only the primary vertical scrollable (depth 0) drives the bar.
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return;
    final scrolled = n.metrics.extentBefore > 0;
    if (scrolled != _scrolled && mounted) setState(() => _scrolled = scrolled);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<DhruvaTokens>()!;
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : tokens.motion.fast,
      child: _scrolled
          ? const GlassChrome(
              key: ValueKey('glass'),
              glass: true,
              edge: GlassEdge.bottom,
              child: SizedBox.expand(),
            )
          : const SizedBox.expand(key: ValueKey('clear')),
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
