import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/session.dart';
import '../auth/session_controller.dart';
import '../theme/theme_mode_toggle.dart';
import '../ui/ui.dart';
import 'command_palette.dart';
import 'mobile_nav.dart';
import 'nav_registry.dart';
import 'notifications.dart';
import 'notifications_panel.dart';
import 'pinned_nav.dart';

/// Breakpoints from the Shell board: >=1280 full nav, 768-1279 icon rail,
/// <768 footer bar.
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
    final density =
        location.startsWith('/pos') ? AppDensity.pos : AppDensity.comfortable;

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
                bottomNavigationBar: narrow
                    ? MobileNavBar(
                        visible: visible, location: location, session: session)
                    : null,
                body: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!narrow)
                      SizedBox(
                        width: compact ? _railWidth : _sideNavWidth,
                        child: _SideNav(
                          items: visible,
                          location: location,
                          compact: compact,
                          session: session,
                        ),
                      ),
                    Expanded(
                      child: Column(
                        children: [
                          if (narrow)
                            AnnotatedRegion<SystemUiOverlayStyle>(
                              // Light clock and icons on a dark header, dark ones on a light header.
                              value: ThemeData.estimateBrightnessForColor(
                                          t.color.background.header) ==
                                      Brightness.dark
                                  ? SystemUiOverlayStyle.light
                                  : SystemUiOverlayStyle.dark,
                              child: ColoredBox(
                                color: t.color.background.header,
                                child: SizedBox(
                                  width: double.infinity,
                                  height: MediaQuery.paddingOf(context).top,
                                ),
                              ),
                            ),
                          _TopBar(
                            session: session,
                            narrow: narrow,
                            visible: visible,
                            title: navItemForPath(location)?.label,
                          ),
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

/// Emerald rounded square with the venue glyph.
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: t.color.background.accent,
        borderRadius: BorderRadius.circular(t.radius.md),
      ),
      child:
          Icon(Icons.point_of_sale, size: 18, color: t.color.content.onAccent),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({
    required this.session,
    required this.narrow,
    required this.visible,
    required this.title,
  });

  final Session? session;
  final bool narrow;
  final List<NavItem> visible;
  final String? title;

  Future<void> _switchOutlet(
      BuildContext context, WidgetRef ref, String outletId) async {
    final ok = await ref.read(sessionProvider.notifier).switchOutlet(outletId);
    if (!context.mounted) return;
    if (ok) {
      final home =
          ref.read(sessionProvider).session?.persona.homeRoute ?? '/dashboard';
      context.go(home);
      showAppToast(context, 'Switched outlet');
    } else {
      showAppToast(context,
          ref.read(sessionProvider).error ?? "Couldn't switch outlet.");
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    await ref.read(sessionProvider.notifier).logout();
    if (context.mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final ext = context.ext;
    final s = session;
    final unread = ref.watch(notificationsProvider).unreadCount;
    final name = s?.user.label ?? '';
    final initial = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();

    final header = t.color.background.header;
    final onHeader = t.color.content.onHeader;
    final plainHeader = header == t.color.background.surface;

    return Container(
      height: 56,
      padding: EdgeInsets.symmetric(horizontal: t.spacing.sm),
      decoration: BoxDecoration(
        color: header,
        border: Border(
          bottom:
              BorderSide(color: plainHeader ? t.color.border.standard : header),
        ),
      ),
      child: IconButtonTheme(
        data: IconButtonThemeData(
            style: IconButton.styleFrom(foregroundColor: onHeader)),
        child: IconTheme.merge(
          data: IconThemeData(color: onHeader),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: onHeader),
            child: Row(
              children: [
                if (narrow) ...[
                  const _BrandMark(),
                  SizedBox(width: t.spacing.sm),
                  Expanded(
                    child: Text(
                      title ?? s?.tenant.name ?? 'POS Billing',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: onHeader),
                    ),
                  ),
                ] else
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _SearchField(
                          onTap: () => showCommandPalette(context, visible)),
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
                            Icon(
                                o.id == s?.outlet.id
                                    ? Icons.check
                                    : Icons.storefront_outlined,
                                size: 18),
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
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                              color: ext.statusGreen, shape: BoxShape.circle),
                        ),
                        SizedBox(width: t.spacing.xs),
                        ConstrainedBox(
                          constraints:
                              BoxConstraints(maxWidth: narrow ? 110 : 160),
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
                if (!narrow)
                  PopupMenuButton<String>(
                    tooltip: 'Language',
                    icon: const Icon(Icons.translate),
                    onSelected: (_) {},
                    itemBuilder: (_) => const [
                      PopupMenuItem<String>(
                          value: 'en', child: Text('English')),
                      PopupMenuItem<String>(
                          enabled: false,
                          value: 'ta',
                          child: Text('Tamil (coming soon)')),
                      PopupMenuItem<String>(
                          enabled: false,
                          value: 'hi',
                          child: Text('Hindi (coming soon)')),
                    ],
                  ),
                if (!narrow) const ThemeModeToggle(),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AppIconButton(
                      icon: Icons.notifications_none,
                      tooltip: 'Notifications',
                      badgeCount: unread == 0 ? null : unread,
                      onPressed: () => showNotificationsPanel(context),
                    ),
                    if (unread > 0)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IgnorePointer(
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: ext.statusRed,
                              shape: BoxShape.circle,
                              border: Border.all(color: header, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (!narrow)
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
                            Text(s?.user.label ?? '',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            Text(s?.persona.name ?? ''),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem<String>(
                        value: 'signout',
                        child: Row(children: [
                          Icon(Icons.logout, size: 18),
                          SizedBox(width: 8),
                          Text('Sign out')
                        ]),
                      ),
                    ],
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: ext.neutralSubtle,
                      foregroundColor: ext.onNeutralSubtle,
                      child: Text(initial,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
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

/// "Search or jump to… Ctrl K" button in the top bar.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final header = t.color.background.header;
    final onHeader = t.color.content.onHeader;
    // On a coloured header the box is a translucent tint of it instead of a light field.
    final plain = header == t.color.background.surface;
    final fill =
        plain ? context.ext.subtleFill : Color.lerp(header, onHeader, 0.08)!;
    final line =
        plain ? t.color.border.standard : Color.lerp(header, onHeader, 0.18)!;
    final hint =
        plain ? t.color.content.muted : onHeader.withValues(alpha: 0.75);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: InkWell(
        borderRadius: BorderRadius.circular(t.radius.md),
        onTap: onTap,
        child: Container(
          height: 36,
          padding: EdgeInsets.symmetric(horizontal: t.spacing.sm),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(t.radius.md),
            border: Border.all(color: line),
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 18, color: hint),
              SizedBox(width: t.spacing.sm),
              Expanded(
                child: Text(
                  'Search or jump to…',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: hint),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: plain ? t.color.background.surface : fill,
                  borderRadius: BorderRadius.circular(t.radius.sm),
                  border: Border.all(color: line),
                ),
                child: Text(
                  'Ctrl K',
                  style: TextStyle(
                      color: plain ? t.color.content.secondary : hint,
                      fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ink side nav, or icon rail when [compact].
class _SideNav extends ConsumerStatefulWidget {
  const _SideNav({
    required this.items,
    required this.location,
    required this.compact,
    required this.session,
  });

  final List<NavItem> items;
  final String location;
  final bool compact;
  final Session? session;

  @override
  ConsumerState<_SideNav> createState() => _SideNavState();
}

class _SideNavState extends ConsumerState<_SideNav> {
  final Set<String> _collapsed = {};

  bool _isSelected(NavItem item) =>
      widget.location == item.route ||
      widget.location.startsWith('${item.route}/');

  void _go(NavItem item) {
    context.go(item.route);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ext = context.ext;
    final compact = widget.compact;
    final pinned = ref.watch(pinnedNavProvider);
    final pinnedItems = [
      for (final id in pinned)
        for (final item in widget.items)
          if (item.id == id) item,
    ];

    final children = <Widget>[];
    if (!compact && pinnedItems.isNotEmpty) {
      children.add(const _GroupLabel(label: 'Pinned'));
      for (final item in pinnedItems) {
        children.add(_NavTile(
          item: item,
          selected: _isSelected(item),
          pinned: true,
          compact: false,
          onTap: () => _go(item),
        ));
      }
    }
    for (final group in navGroups) {
      final groupItems = widget.items
          .where((i) => i.group == group && !pinnedItems.contains(i))
          .toList();
      if (groupItems.isEmpty) continue;
      final open = !_collapsed.contains(group);
      if (!compact) {
        children.add(_GroupLabel(
          label: group,
          expanded: open,
          onTap: () => setState(() {
            if (!_collapsed.add(group)) _collapsed.remove(group);
          }),
        ));
      }
      if (open || compact) {
        for (final item in groupItems) {
          children.add(_NavTile(
            item: item,
            selected: _isSelected(item),
            pinned: pinned.contains(item.id),
            compact: compact,
            onTap: () => _go(item),
          ));
        }
      }
      if (compact) children.add(SizedBox(height: t.spacing.sm));
    }

    final s = widget.session;
    final name = s?.user.label ?? '';
    final initial = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();

    return Container(
      color: ext.navBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 56,
            padding:
                EdgeInsets.symmetric(horizontal: compact ? 0 : t.spacing.md),
            alignment: compact ? Alignment.center : Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: ext.navDivider)),
            ),
            child: Row(
              mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
              children: [
                const _BrandMark(),
                if (!compact) ...[
                  SizedBox(width: t.spacing.sm),
                  Expanded(
                    child: Text(
                      s?.tenant.name ?? 'POS Billing',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: ext.navForegroundActive),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                  vertical: t.spacing.sm, horizontal: t.spacing.xs),
              children: children,
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 0 : t.spacing.md,
              vertical: t.spacing.sm,
            ),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: ext.navDivider)),
            ),
            child: Row(
              mainAxisAlignment:
                  compact ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: ext.navActive,
                  foregroundColor: ext.navForegroundActive,
                  child: Text(initial,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                if (!compact) ...[
                  SizedBox(width: t.spacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: ext.navForegroundActive,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          s?.persona.name ?? '',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: ext.navMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.label, this.expanded, this.onTap});

  final String label;
  final bool? expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ext = context.ext;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(t.radius.sm),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            t.spacing.sm, t.spacing.md, t.spacing.sm, t.spacing.xs),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: ext.navMuted,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
              ),
            ),
            if (expanded != null)
              Icon(
                expanded! ? Icons.expand_less : Icons.expand_more,
                size: 16,
                color: ext.navMuted,
              ),
          ],
        ),
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
      showAppToast(context,
          'Unpin something first. You can pin up to $maxPinnedNav items.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ext = context.ext;
    final item = widget.item;
    final fg = widget.selected ? ext.navForegroundActive : ext.navForeground;

    if (widget.compact) {
      return Tooltip(
        message: item.label,
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: widget.selected ? ext.navActive : null,
              borderRadius: BorderRadius.circular(t.radius.md),
            ),
            child: IconButton(
              icon: Icon(item.icon, color: fg),
              isSelected: widget.selected,
              onPressed: widget.onTap,
              selectedIcon: Icon(item.icon, color: ext.navAccent),
            ),
          ),
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: widget.selected
              ? ext.navActive
              : (_hover ? ext.navSubActive : null),
          borderRadius: BorderRadius.circular(t.radius.md),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            ListTile(
              dense: true,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(t.radius.md)),
              iconColor: fg,
              textColor: fg,
              leading: Icon(
                item.icon,
                color: widget.selected ? ext.navAccent : ext.navMuted,
              ),
              title: Text(
                item.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontWeight:
                      widget.selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              onTap: widget.onTap,
              trailing: (_hover || widget.pinned)
                  ? IconButton(
                      tooltip: widget.pinned ? 'Unpin' : 'Pin to top',
                      color: ext.navMuted,
                      icon: Icon(
                        widget.pinned
                            ? Icons.push_pin
                            : Icons.push_pin_outlined,
                        size: 18,
                      ),
                      onPressed: _togglePin,
                    )
                  : null,
            ),
            if (widget.selected)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                    child: Container(width: 2, color: ext.navAccent)),
              ),
          ],
        ),
      ),
    );
  }
}
