import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/session.dart';
import '../auth/session_controller.dart';
import '../theme/theme_providers.dart';
import '../ui/ui.dart';
import '../../features/guest_requests/presentation/guest_orders_badge.dart';
import 'nav_registry.dart';

/// The four pages each persona gets in the phone footer bar. Anything missing
/// from the persona's permissions is skipped and the gap is filled in menu order.
const _personaTabs = <String, List<String>>{
  'admin': ['dashboard', 'pos', 'orders', 'menu'],
  'manager': ['dashboard', 'pos', 'orders', 'floor'],
  'cashier': ['pos', 'orders', 'floor', 'bar-tabs'],
  'bartender': ['bar-tabs', 'pos', 'orders', 'availability'],
  'captain': ['floor', 'pos', 'guest-orders', 'bar-tabs'],
  'waiter': ['floor', 'pos', 'guest-orders', 'ready'],
  'chef': ['kds', 'ready', 'availability', 'stock-count'],
  'storekeeper': ['stock-count', 'inventory', 'procurement', 'availability'],
};

const _tabCount = 4;

/// Tabs share a fifth of the screen each, so the longest names get a shorter label.
const _shortLabels = <String, String>{
  'kds': 'Kitchen',
  'ready': 'Ready',
  'menu': 'Menu',
};

/// The pages shown as tabs in the footer bar for [session].
List<NavItem> mobileTabs(Session? session, List<NavItem> visible) {
  final byId = {for (final i in visible) i.id: i};
  final tabs = <NavItem>[
    for (final id in _personaTabs[session?.persona.key] ?? const <String>[])
      if (byId[id] != null) byId[id]!,
  ];
  for (final item in visible) {
    if (tabs.length >= _tabCount) break;
    if (!item.placeholder && !tabs.contains(item)) tabs.add(item);
  }
  return tabs.take(_tabCount).toList();
}

bool _isOn(String location, NavItem item) =>
    location == item.route || location.startsWith('${item.route}/');

/// Footer bar for phones: four pages plus More, which opens every other page.
class MobileNavBar extends ConsumerWidget {
  const MobileNavBar({
    super.key,
    required this.visible,
    required this.location,
    required this.session,
  });

  final List<NavItem> visible;
  final String location;
  final Session? session;

  void _openMore(BuildContext context, List<NavItem> tabs) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _MoreSheet(
        pages: [
          for (final i in visible)
            if (!tabs.contains(i)) i
        ],
        location: location,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final ext = context.ext;
    final tabs = mobileTabs(session, visible);

    if (tabs.isEmpty) {
      return Material(
        color: t.color.background.surface,
        child: SafeArea(
          child: SizedBox(
            height: 56,
            child: Center(
              child: TextButton.icon(
                onPressed: () => _openMore(context, tabs),
                icon: const Icon(Icons.menu),
                label: const Text('More'),
              ),
            ),
          ),
        ),
      );
    }

    final onTab = tabs.indexWhere((i) => _isOn(location, i));
    final selected = onTab == -1 ? tabs.length : onTab;
    final accent = t.color.background.accent;
    final muted = t.color.content.muted;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.color.border.standard)),
      ),
      child: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: t.color.background.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          height: 68,
          indicatorColor: ext.accentSubtle,
          iconTheme: WidgetStateProperty.resolveWith(
            (s) => IconThemeData(
                size: 24,
                color: s.contains(WidgetState.selected) ? accent : muted),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (s) => TextStyle(
              fontSize: 11,
              fontWeight: s.contains(WidgetState.selected)
                  ? FontWeight.w600
                  : FontWeight.w500,
              color: s.contains(WidgetState.selected) ? accent : muted,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: selected,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (i) {
            if (i < tabs.length) {
              context.go(tabs[i].route);
            } else {
              _openMore(context, tabs);
            }
          },
          destinations: [
            for (final item in tabs)
              NavigationDestination(
                icon: item.id == guestOrdersNavId
                    ? GuestOrdersTabIcon(icon: item.icon)
                    : Icon(item.icon),
                label: _shortLabels[item.id] ?? item.label,
                tooltip: item.label,
              ),
            const NavigationDestination(
              icon: Icon(Icons.menu),
              label: 'More',
              tooltip: 'More pages',
            ),
          ],
        ),
      ),
    );
  }
}

/// Everything not in the footer bar, plus language, dark mode and sign out.
class _MoreSheet extends ConsumerStatefulWidget {
  const _MoreSheet({required this.pages, required this.location});

  final List<NavItem> pages;
  final String location;

  @override
  ConsumerState<_MoreSheet> createState() => _MoreSheetState();
}

class _MoreSheetState extends ConsumerState<_MoreSheet> {
  String _query = '';

  Future<void> _signOut() async {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    await ref.read(sessionProvider.notifier).logout();
    router.go('/login');
  }

  void _open(NavItem item) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go(item.route);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ext = context.ext;
    final text = Theme.of(context).textTheme;
    final session = ref.watch(sessionProvider).session;
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final name = session?.user.label ?? '';
    final initial = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();

    final q = _query.trim().toLowerCase();
    final shown = [
      for (final p in widget.pages)
        if (q.isEmpty || p.label.toLowerCase().contains(q)) p,
    ];

    final rows = <Widget>[];
    for (final group in navGroups) {
      final inGroup = shown.where((p) => p.group == group).toList();
      if (inGroup.isEmpty) continue;
      rows.add(Padding(
        padding: EdgeInsets.fromLTRB(
            t.spacing.sm, t.spacing.md, t.spacing.sm, t.spacing.xs),
        child: Text(
          group.toUpperCase(),
          style: text.labelSmall
              ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
      ));
      for (final p in inGroup) {
        final on = _isOn(widget.location, p);
        rows.add(Material(
          color: on ? ext.accentSubtle : Colors.transparent,
          borderRadius: BorderRadius.circular(t.radius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(t.radius.md),
            onTap: () => _open(p),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: t.spacing.sm),
                child: Row(
                  children: [
                    Icon(
                      p.icon,
                      size: 20,
                      color: on
                          ? t.color.background.accent
                          : t.color.content.secondary,
                    ),
                    SizedBox(width: t.spacing.sm + 4),
                    Expanded(
                      child: Text(
                        p.label,
                        style: text.bodyMedium?.copyWith(
                          color: on ? t.color.background.accent : null,
                          fontWeight: on ? FontWeight.w600 : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ));
      }
    }

    return ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: t.spacing.md),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: ext.accentSubtle,
                  foregroundColor: t.color.background.accent,
                  child: Text(initial,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                SizedBox(width: t.spacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: text.titleSmall,
                          overflow: TextOverflow.ellipsis),
                      Text(
                        '${session?.persona.name ?? ''} · ${session?.outlet.name ?? ''}',
                        style: text.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: t.spacing.sm + 4),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: t.spacing.md),
            child: Row(
              children: [
                Expanded(
                  child: PopupMenuButton<String>(
                    tooltip: 'Language',
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
                    child: const _QuickAction(
                        icon: Icons.translate, label: 'English'),
                  ),
                ),
                SizedBox(width: t.spacing.sm),
                Expanded(
                  child: _QuickAction(
                    icon: isDark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                    label: isDark ? 'Light mode' : 'Dark mode',
                    onTap: () => ref.read(themeModeProvider.notifier).toggle(),
                  ),
                ),
                SizedBox(width: t.spacing.sm),
                Expanded(
                  child: _QuickAction(
                    icon: Icons.logout,
                    label: 'Sign out',
                    color: t.color.content.danger,
                    onTap: _signOut,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: t.spacing.sm + 4),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: t.spacing.md),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search ${widget.pages.length} pages',
                prefixIcon: const Icon(Icons.search, size: 20),
              ),
            ),
          ),
          Flexible(
            child: shown.isEmpty
                ? Padding(
                    padding: EdgeInsets.all(t.spacing.lg),
                    child: Center(
                      child: Text('No page matches "$_query".',
                          style: text.bodySmall),
                    ),
                  )
                : ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.fromLTRB(
                      t.spacing.sm,
                      0,
                      t.spacing.sm,
                      t.spacing.md,
                    ),
                    children: rows,
                  ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction(
      {required this.icon, required this.label, this.onTap, this.color});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fg = color ?? t.color.content.secondary;
    return Material(
      color: t.color.background.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radius.md),
        side: BorderSide(color: t.color.border.standard),
      ),
      child: InkWell(
        customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.radius.md)),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w500, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
