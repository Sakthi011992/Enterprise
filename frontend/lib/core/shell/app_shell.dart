import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/session.dart';
import '../auth/session_controller.dart';
import '../theme/app_theme.dart';
import '../theme/theme_mode_toggle.dart';
import '../ui/ui.dart';
import 'command_palette.dart';
import 'nav_registry.dart';
import 'notifications.dart';
import 'notifications_panel.dart';
import 'pinned_nav.dart';

/// Breakpoints from the Shell board: >=1280 full nav, 768-1279 icon rail,
/// <768 drawer.
const _wideBreakpoint = 1280.0;
const _railBreakpoint = 768.0;
const _railWidth = 72.0;
const _sideNavWidth = 248.0;

/// Shell around every signed-in page. [location] is the matched path, used to
/// pick the nav selection and the density.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).session;
    // Keeps the unread-count poll alive while the shell is mounted.
    ref.watch(notificationsProvider);
    final visible = visibleNavItems(session);
    final density = location.startsWith('/pos') ? AppDensity.pos : AppDensity.comfortable;

    return DensityScope(
      density: density,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
              showCommandPalette(context, visible),
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
              showCommandPalette(context, visible),
        },
        child: Focus(
          autofocus: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final narrow = width < _railBreakpoint;
              final compact = !narrow && width < _wideBreakpoint;
              final t = context.tokens;

              return Scaffold(
                backgroundColor: t.color.background.canvas,
                drawer: narrow
                    ? Drawer(
                        child: SafeArea(
                          child: _SideNav(
                            items: visible,
                            location: location,
                            compact: false,
                            onNavigate: () => Navigator.of(context).pop(),
                          ),
                        ),
                      )
                    : null,
                body: Column(
                  children: [
                    _TopBar(session: session, narrow: narrow, visible: visible),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!narrow)
                            SizedBox(
                              width: compact ? _railWidth : _sideNavWidth,
                              child: _SideNav(
                                items: visible,
                                location: location,
                                compact: compact,
                              ),
                            ),
                          if (!narrow) VerticalDivider(width: 1, color: t.color.border.subtle),
                          Expanded(child: child),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.session, required this.narrow, required this.visible});

  final Session? session;
  final bool narrow;
  final List<NavItem> visible;

  Future<void> _switchOutlet(BuildContext context, WidgetRef ref, String outletId) async {
    final ok = await ref.read(sessionProvider.notifier).switchOutlet(outletId);
    if (!context.mounted) return;
    if (ok) {
      final home = ref.read(sessionProvider).session?.persona.homeRoute ?? '/dashboard';
      context.go(home);
      showAppToast(context, 'Switched outlet');
    } else {
      showAppToast(context, ref.read(sessionProvider).error ?? "Couldn't switch outlet.");
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    await ref.read(sessionProvider.notifier).logout();
    if (context.mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final s = session;
    final unread = ref.watch(notificationsProvider).unreadCount;
    final name = s?.user.label ?? '';
    final initial = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();

    return Container(
      height: 52,
      padding: EdgeInsets.symmetric(horizontal: t.spacing.sm),
      decoration: BoxDecoration(
        color: t.color.background.raised,
        border: Border(bottom: BorderSide(color: t.color.border.subtle)),
      ),
      child: Row(
        children: [
          if (narrow)
            AppIconButton(
              icon: Icons.menu,
              tooltip: 'Open menu',
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          Icon(Icons.point_of_sale, color: t.color.background.accent),
          SizedBox(width: t.spacing.xs),
          Flexible(
            child: Text(
              s?.tenant.name ?? 'POS Billing',
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          SizedBox(width: t.spacing.md),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _SearchField(onTap: () => showCommandPalette(context, visible)),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Switch outlet',
            onSelected: (id) => _switchOutlet(context, ref, id),
            itemBuilder: (_) => [
              for (final o in s?.outlets ?? const <OutletAccess>[])
                PopupMenuItem<String>(
                  value: o.id,
                  child: Row(
                    children: [
                      Icon(o.id == s?.outlet.id ? Icons.check : Icons.storefront_outlined, size: 18),
                      SizedBox(width: t.spacing.sm),
                      Text('${o.name} (${o.persona.name})'),
                    ],
                  ),
                ),
            ],
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: t.spacing.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.storefront_outlined, size: 18),
                  SizedBox(width: t.spacing.xs),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      s?.outlet.name ?? 'Outlet',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Language',
            icon: const Icon(Icons.translate),
            onSelected: (_) {},
            itemBuilder: (_) => const [
              PopupMenuItem<String>(value: 'en', child: Text('English')),
              PopupMenuItem<String>(enabled: false, value: 'ta', child: Text('Tamil (coming soon)')),
              PopupMenuItem<String>(enabled: false, value: 'hi', child: Text('Hindi (coming soon)')),
            ],
          ),
          const ThemeModeToggle(),
          AppIconButton(
            icon: Icons.notifications_none,
            tooltip: 'Notifications',
            badgeCount: unread == 0 ? null : unread,
            onPressed: () => showNotificationsPanel(context),
          ),
          PopupMenuButton<String>(
            tooltip: 'Account',
            onSelected: (v) {
              if (v == 'signout') _signOut(context, ref);
            },
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(s?.user.label ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(s?.persona.name ?? ''),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'signout',
                child: Row(children: [Icon(Icons.logout, size: 18), SizedBox(width: 8), Text('Sign out')]),
              ),
            ],
            child: CircleAvatar(
              radius: 16,
              backgroundColor: t.color.background.accent,
              foregroundColor: t.color.content.onAccent,
              child: Text(initial),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Search or jump to… Ctrl K" button in the top bar.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: InkWell(
        borderRadius: BorderRadius.circular(t.radius.md),
        onTap: onTap,
        child: Container(
          height: 36,
          padding: EdgeInsets.symmetric(horizontal: t.spacing.sm),
          decoration: BoxDecoration(
            color: t.color.background.surface,
            borderRadius: BorderRadius.circular(t.radius.md),
            border: Border.all(color: t.color.border.subtle),
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 18, color: t.color.content.muted),
              SizedBox(width: t.spacing.sm),
              Expanded(
                child: Text(
                  'Search or jump to…',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.color.content.muted),
                ),
              ),
              Text('Ctrl K', style: TextStyle(color: t.color.content.secondary, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Side nav (or icon rail when [compact], or drawer body).
class _SideNav extends ConsumerWidget {
  const _SideNav({
    required this.items,
    required this.location,
    required this.compact,
    this.onNavigate,
  });

  final List<NavItem> items;
  final String location;
  final bool compact;
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final pinned = ref.watch(pinnedNavProvider);
    final pinnedItems = [
      for (final id in pinned)
        for (final item in items)
          if (item.id == id) item,
    ];

    bool isSelected(NavItem item) => location == item.route || location.startsWith('${item.route}/');

    void go(NavItem item) {
      onNavigate?.call();
      context.go(item.route);
    }

    final children = <Widget>[];
    if (!compact && pinnedItems.isNotEmpty) {
      children.add(_GroupLabel(label: 'Pinned'));
      for (final item in pinnedItems) {
        children.add(_NavTile(
          item: item,
          selected: isSelected(item),
          pinned: true,
          compact: false,
          onTap: () => go(item),
        ));
      }
    }
    for (final group in navGroups) {
      final groupItems = items.where((i) => i.group == group && !pinnedItems.contains(i)).toList();
      if (groupItems.isEmpty) continue;
      if (!compact) children.add(_GroupLabel(label: group));
      for (final item in groupItems) {
        children.add(_NavTile(
          item: item,
          selected: isSelected(item),
          pinned: pinned.contains(item.id),
          compact: compact,
          onTap: () => go(item),
        ));
      }
      if (compact) children.add(SizedBox(height: t.spacing.sm));
    }

    return ListView(
      padding: EdgeInsets.symmetric(vertical: t.spacing.sm, horizontal: t.spacing.xs),
      children: children,
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.fromLTRB(t.spacing.sm, t.spacing.md, t.spacing.sm, t.spacing.xs),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: t.color.content.muted),
      ),
    );
  }
}

class _NavTile extends ConsumerStatefulWidget {
  const _NavTile({
    required this.item,
    required this.selected,
    required this.pinned,
    required this.compact,
    required this.onTap,
  });

  final NavItem item;
  final bool selected;
  final bool pinned;
  final bool compact;
  final VoidCallback onTap;

  @override
  ConsumerState<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends ConsumerState<_NavTile> {
  bool _hover = false;

  void _togglePin() {
    final ok = ref.read(pinnedNavProvider.notifier).toggle(widget.item.id);
    if (!ok) {
      showAppToast(context, 'Unpin something first. You can pin up to $maxPinnedNav items.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final item = widget.item;

    if (widget.compact) {
      return Tooltip(
        message: item.label,
        child: IconButton(
          icon: Icon(item.icon),
          isSelected: widget.selected,
          onPressed: widget.onTap,
          selectedIcon: Icon(item.icon, color: t.color.background.accent),
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: widget.selected ? t.color.background.surface : null,
          borderRadius: BorderRadius.circular(t.radius.md),
        ),
        child: ListTile(
          dense: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radius.md)),
          leading: Icon(item.icon, color: widget.selected ? t.color.background.accent : null),
          title: Text(item.label, overflow: TextOverflow.ellipsis),
          selected: widget.selected,
          onTap: widget.onTap,
          trailing: (_hover || widget.pinned)
              ? IconButton(
                  tooltip: widget.pinned ? 'Unpin' : 'Pin to top',
                  icon: Icon(widget.pinned ? Icons.push_pin : Icons.push_pin_outlined, size: 18),
                  onPressed: _togglePin,
                )
              : null,
        ),
      ),
    );
  }
}
