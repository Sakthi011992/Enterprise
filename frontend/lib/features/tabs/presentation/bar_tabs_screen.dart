import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/auth/permission_keys.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/realtime/realtime_client.dart';
import '../../../core/ui/ui.dart';
import '../../pos/presentation/dialogs/dialog_frame.dart';
import '../../pos/presentation/pos_format.dart';
import '../../pos/presentation/pos_order_controller.dart';
import '../data/tabs_models.dart';
import '../data/tabs_repository.dart';
import '../domain/tab_rules.dart';
import 'locker_dialogs.dart';
import 'open_tab_dialog.dart';
import 'tabs_providers.dart';

/// `/tabs`: open bar tabs with their spend against limit, and the bottle locker.
/// Design: BarTabs board. Works on desktop, tablet and phone.
class BarTabsScreen extends ConsumerStatefulWidget {
  const BarTabsScreen({super.key});

  @override
  ConsumerState<BarTabsScreen> createState() => _BarTabsScreenState();
}

enum _TabFilter { open, nearLimit, closedToday }

class _BarTabsScreenState extends ConsumerState<BarTabsScreen> {
  _TabFilter _filter = _TabFilter.open;
  String? _bartenderId;

  void _refresh() => ref.invalidate(tabsPageProvider(_bartenderId));

  /// Runs a repository call. Shows the friendly error and refreshes either way.
  Future<T?> _run<T>(Future<T> Function() call, {String? success}) async {
    try {
      final result = await call();
      if (!mounted) return result;
      if (success != null) showAppToast(context, success);
      _refresh();
      return result;
    } catch (e) {
      if (mounted) {
        showAppToast(context, tabErrorMessage(ApiError.from(e)));
        _refresh();
      }
      return null;
    }
  }

  Future<void> _openTab() async {
    final tab = await showOpenTabDialog(context);
    if (tab == null || !mounted) return;
    _refresh();
    showAppToast(
      context,
      '${tab.number} opened for ${tab.guestName}.',
      actionLabel: 'Add items',
      onAction: () => context.go('/pos/${tab.orderId}'),
    );
  }

  Future<void> _edit(TabView tab) async {
    final updated = await showEditTabDialog(context, tab);
    if (updated == null || !mounted) return;
    _refresh();
    showAppToast(context, '${updated.number} updated.');
  }

  Future<void> _closeAndPay(TabView tab) async {
    final result = await _run(
      () => ref.read(tabsRepositoryProvider).closeTab(tab.id),
    );
    if (result == null || !mounted) return;
    if (result.depositToReturn != '0.00') {
      showAppToast(
        context,
        'Return ${formatWire(result.depositToReturn)} of the deposit to the guest.',
      );
    }
    context.go('/pos/${result.orderId}/pay');
  }

  Future<void> _moveToTable(TabView tab) async {
    final tableId = await showDialog<String>(
      context: context,
      builder: (_) => const _MoveTableDialog(),
    );
    if (tableId == null || !mounted) return;
    await _run(
      () => ref.read(tabsRepositoryProvider).moveToTable(tab.id, tableId: tableId),
      success: '${tab.number} moved to the table.',
    );
  }

  Future<void> _void(TabView tab) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Void ${tab.number}?',
      message: 'This empty tab closes and leaves the list.',
      confirmLabel: 'Void tab',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run(
      () => ref.read(tabsRepositoryProvider).voidTab(tab.id, reason: 'Voided from the bar tabs list'),
      success: '${tab.number} voided.',
    );
  }

  static String _filterLabel(_TabFilter f) => switch (f) {
        _TabFilter.open => 'Open',
        _TabFilter.nearLimit => 'Near limit',
        _TabFilter.closedToday => 'Closed today',
      };

  static List<TabView> _visible(List<TabView> items, _TabFilter filter) => switch (filter) {
        _TabFilter.open => [for (final t in items) if (t.isOpen) t],
        _TabFilter.nearLimit => [for (final t in items) if (t.isOpen && t.nearLimit) t],
        _TabFilter.closedToday => [for (final t in items) if (t.isClosed) t],
      };

  /// Action buttons for one tab. Open tabs at a seat or table close and pay.
  /// Queue tabs move to a table first (design T-08).
  Widget _actions(TabView tab, {required bool canEdit}) {
    if (!tab.isOpen || !canEdit) return const SizedBox.shrink();
    final atSeat = tab.linkType == TabLinkTypes.barSeat || tab.linkType == TabLinkTypes.table;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        AppButton(
          label: 'Add items',
          size: AppControlSize.md,
          variant: AppButtonVariant.secondary,
          onPressed: () => context.go('/pos/${tab.orderId}'),
        ),
        AppButton(
          label: 'Edit',
          size: AppControlSize.md,
          variant: AppButtonVariant.ghost,
          onPressed: () => _edit(tab),
        ),
        if (atSeat)
          AppButton(
            label: 'Close & pay',
            size: AppControlSize.md,
            variant: AppButtonVariant.primary,
            onPressed: () => _closeAndPay(tab),
          )
        else
          AppButton(
            label: 'Move to table',
            size: AppControlSize.md,
            variant: AppButtonVariant.ghost,
            onPressed: () => _moveToTable(tab),
          ),
        if (tab.spentValue == 0)
          AppButton(
            label: 'Void',
            size: AppControlSize.md,
            variant: AppButtonVariant.ghost,
            onPressed: () => _void(tab),
          ),
      ],
    );
  }

  List<AppColumn<TabView>> _columns(bool canEdit) => [
        AppColumn<TabView>(
          label: 'Tab',
          width: 90,
          cell: (tab) => Text(tab.number, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        AppColumn<TabView>(label: 'Guest', cell: (tab) => Text(tab.guestName)),
        AppColumn<TabView>(label: 'Pre-auth', cell: (tab) => Text(tab.securityLabel)),
        AppColumn<TabView>(
          label: 'Spent / limit',
          numeric: true,
          cell: (tab) => Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('${formatRupees(tab.spentValue)} / ${formatRupees(tab.tabLimitValue)}'),
              if (tab.isOpen && tab.nearLimit) const StatusBadge(label: 'Near limit', tone: StatusTone.warning),
              if (tab.isClosed) const StatusBadge(label: 'Closed'),
            ],
          ),
        ),
        AppColumn<TabView>(
          label: 'Opened',
          width: 90,
          cell: (tab) => Text(tab.openedAt == null ? '—' : formatClock(tab.openedAt!.toLocal())),
        ),
        AppColumn<TabView>(label: 'Linked to', cell: (tab) => Text(_linkText(tab))),
        AppColumn<TabView>(
          label: 'Actions',
          width: 400,
          cell: (tab) => _actions(tab, canEdit: canEdit),
        ),
      ];

  static String _linkText(TabView tab) {
    final label = tab.linkLabel;
    if (label != null && label.isNotEmpty) return label;
    final table = tab.table;
    if (table != null) return table.name;
    if (tab.linkType == TabLinkTypes.none) return '—';
    return linkTypeLabel(tab.linkType);
  }

  Widget _tabCard(TabView tab, {required bool canEdit}) {
    final t = context.tokens;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${tab.number} · ${tab.guestName}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (tab.isOpen && tab.nearLimit)
                const StatusBadge(label: 'Near limit', tone: StatusTone.warning)
              else if (tab.isClosed)
                const StatusBadge(label: 'Closed')
              else
                const StatusBadge(label: 'Open', tone: StatusTone.success),
            ],
          ),
          SizedBox(height: t.spacing.xs),
          Text(tab.securityLabel),
          Text(
            '${formatRupees(tab.spentValue)} / ${formatRupees(tab.tabLimitValue)} · ${_linkText(tab)}',
          ),
          if (tab.isOpen && canEdit) ...[
            SizedBox(height: t.spacing.sm),
            _actions(tab, canEdit: canEdit),
          ],
        ],
      ),
    );
  }

  Widget _openTabsBody(List<TabView> all, {required bool canEdit}) {
    final t = context.tokens;
    final visible = _visible(all, _filter);
    if (visible.isEmpty) {
      return const EmptyState(
        title: 'No tabs here',
        message: 'Open a tab for a guest and it shows here.',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return ListView(
            children: [
              AppDataTable<TabView>(columns: _columns(canEdit), rows: visible),
            ],
          );
        }
        return ListView.separated(
          itemCount: visible.length,
          separatorBuilder: (_, __) => SizedBox(height: t.spacing.sm),
          itemBuilder: (_, i) => _tabCard(visible[i], canEdit: canEdit),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final canView = can(ref, Perm.salesTabOpen, AccessLevel.view);
    final canEdit = can(ref, Perm.salesTabOpen, AccessLevel.limited);

    // A near-limit warning from the server refreshes the list and says so.
    ref.listen(realtimeEventProvider(RealtimeEvents.tabNearLimit), (_, next) {
      final event = next.valueOrNull;
      if (event == null) return;
      _refresh();
      final number = event.payload['number'];
      showAppToast(context, number == null ? 'A tab is near its limit.' : 'Tab $number is near its limit.');
    });

    final body = !canView
        ? const EmptyState(title: "You can't see bar tabs on this device.")
        : DefaultTabController(
            length: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageHeader(
                  title: 'Bar tabs',
                  actions: [
                    if (canEdit)
                      AppButton(
                        label: 'Open a new tab',
                        icon: Icons.add,
                        variant: AppButtonVariant.primary,
                        onPressed: _openTab,
                      ),
                  ],
                ),
                const TabBar(
                  tabs: [
                    Tab(text: 'Open tabs'),
                    Tab(text: 'Bottle locker'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _OpenTabsPane(
                        filterLabel: _filterLabel,
                        filter: _filter,
                        bartenderId: _bartenderId,
                        onFilter: (f) => setState(() => _filter = f),
                        onBartender: (id) => setState(() => _bartenderId = id),
                        onRetry: _refresh,
                        bodyBuilder: (items) => _openTabsBody(items, canEdit: canEdit),
                      ),
                      _LockerTab(canEdit: canEdit),
                    ],
                  ),
                ),
              ],
            ),
          );

    return DensityScope(
      density: AppDensity.pos,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: t.spacing.xs),
            child: body,
          ),
        ),
      ),
    );
  }
}

/// Filter chips, bartender filter and the tab list for the "Open tabs" tab.
class _OpenTabsPane extends ConsumerWidget {
  const _OpenTabsPane({
    required this.filterLabel,
    required this.filter,
    required this.bartenderId,
    required this.onFilter,
    required this.onBartender,
    required this.onRetry,
    required this.bodyBuilder,
  });

  final String Function(_TabFilter) filterLabel;
  final _TabFilter filter;
  final String? bartenderId;
  final ValueChanged<_TabFilter> onFilter;
  final ValueChanged<String?> onBartender;
  final VoidCallback onRetry;
  final Widget Function(List<TabView>) bodyBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final page = ref.watch(tabsPageProvider(bartenderId));
    final staff = ref.watch(managerStaffProvider).valueOrNull ?? const [];
    final staffIds = {for (final s in staff) s.userId};

    return Padding(
      padding: EdgeInsets.all(t.spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: t.spacing.sm,
            runSpacing: t.spacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final f in _TabFilter.values)
                PosChoiceChip(
                  label: filterLabel(f),
                  selected: filter == f,
                  minHeight: 44,
                  onTap: () => onFilter(f),
                ),
              SizedBox(
                width: 240,
                child: AppSelect<String?>(
                  label: 'Bartender',
                  value: staffIds.contains(bartenderId) || bartenderId == null ? bartenderId : null,
                  items: [
                    const AppSelectItem<String?>(null, 'All bartenders'),
                    for (final s in staff) AppSelectItem<String?>(s.userId, s.displayName),
                  ],
                  onChanged: onBartender,
                ),
              ),
            ],
          ),
          SizedBox(height: t.spacing.md),
          Expanded(
            child: page.when(
              loading: () => const DelayedSkeleton(child: SkeletonList()),
              error: (e, _) => ErrorState(message: ApiError.from(e).message, onRetry: onRetry),
              data: (data) => bodyBuilder(data.items),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Bottle locker" tab: stored bottles with serve, edit and remove.
class _LockerTab extends ConsumerStatefulWidget {
  const _LockerTab({required this.canEdit});

  final bool canEdit;

  @override
  ConsumerState<_LockerTab> createState() => _LockerTabState();
}

class _LockerTabState extends ConsumerState<_LockerTab> {
  String _search = '';

  Future<void> _store() async {
    final locker = await showStoreBottleDialog(context);
    if (locker == null || !mounted) return;
    ref.invalidate(lockersProvider);
    showAppToast(context, '${locker.bottleName} stored for ${locker.guestLabel}.');
  }

  Future<void> _serve(LockerView locker) async {
    final updated = await showServeBottleDialog(context, locker);
    if (updated == null || !mounted) return;
    ref.invalidate(lockersProvider);
    showAppToast(context, '${updated.remainingMl} ml left in ${updated.bottleName}.');
  }

  Future<void> _edit(LockerView locker) async {
    final updated = await showEditLockerDialog(context, locker);
    if (updated == null || !mounted) return;
    ref.invalidate(lockersProvider);
  }

  Future<void> _remove(LockerView locker) async {
    final updated = await showRemoveLockerDialog(context, locker);
    if (updated == null || !mounted) return;
    ref.invalidate(lockersProvider);
    showAppToast(context, '${updated.bottleName} removed.');
  }

  List<AppColumn<LockerView>> _columns() => [
        AppColumn<LockerView>(label: 'Guest', cell: (l) => Text(l.guestLabel)),
        AppColumn<LockerView>(label: 'Bottle', cell: (l) => Text(l.bottleName)),
        AppColumn<LockerView>(
          label: 'Remaining',
          numeric: true,
          width: 110,
          cell: (l) => Text('${l.remainingMl} ml'),
        ),
        AppColumn<LockerView>(
          label: 'Stored',
          width: 100,
          cell: (l) => Text(l.storedAt == null ? '—' : shortDate(l.storedAt!.toLocal())),
        ),
        AppColumn<LockerView>(
          label: 'Expires',
          width: 150,
          cell: (l) => Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(l.expiresAt == null ? '—' : shortDate(l.expiresAt!)),
              if (l.expired) const StatusBadge(label: 'Expired', tone: StatusTone.danger),
            ],
          ),
        ),
        AppColumn<LockerView>(
          label: 'Actions',
          width: 300,
          cell: (l) => !widget.canEdit
              ? const SizedBox.shrink()
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppButton(
                      label: 'Serve',
                      size: AppControlSize.md,
                      variant: AppButtonVariant.primary,
                      onPressed: () => _serve(l),
                    ),
                    AppButton(
                      label: 'Edit',
                      size: AppControlSize.md,
                      variant: AppButtonVariant.ghost,
                      onPressed: () => _edit(l),
                    ),
                    AppButton(
                      label: 'Remove',
                      size: AppControlSize.md,
                      variant: AppButtonVariant.ghost,
                      onPressed: () => _remove(l),
                    ),
                  ],
                ),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final lockers = ref.watch(lockersProvider);
    return Padding(
      padding: EdgeInsets.all(t.spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              label: 'Store bottle',
              variant: AppButtonVariant.primary,
              onPressed: widget.canEdit ? _store : null,
            ),
          ),
          SizedBox(height: t.spacing.md),
          Expanded(
            child: lockers.when(
              loading: () => const DelayedSkeleton(child: SkeletonList()),
              error: (e, _) => ErrorState(
                message: ApiError.from(e).message,
                onRetry: () => ref.invalidate(lockersProvider),
              ),
              data: (items) {
                final query = _search.toLowerCase();
                final rows = [
                  for (final l in items)
                    if (query.isEmpty ||
                        l.guestName.toLowerCase().contains(query) ||
                        l.bottleName.toLowerCase().contains(query))
                      l,
                ];
                return ListView(
                  children: [
                    AppDataTable<LockerView>(
                      columns: _columns(),
                      rows: rows,
                      searchHint: 'Search guest or bottle',
                      onSearch: (s) => setState(() => _search = s),
                      empty: const EmptyState(
                        title: 'No bottles stored',
                        message: 'Store a bottle when a guest leaves one for next time.',
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Picks a free table for a queue or walk-in tab. Resolves to the table id.
class _MoveTableDialog extends ConsumerStatefulWidget {
  const _MoveTableDialog();

  @override
  ConsumerState<_MoveTableDialog> createState() => _MoveTableDialogState();
}

class _MoveTableDialogState extends ConsumerState<_MoveTableDialog> {
  String? _tableId;

  @override
  Widget build(BuildContext context) {
    final tables = ref.watch(posTablesProvider);
    return PosDialogFrame(
      title: 'Move to table',
      subtitle: 'The tab and its order move to the table.',
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Move',
          variant: AppButtonVariant.primary,
          onPressed: _tableId == null ? null : () => Navigator.of(context).pop(_tableId),
        ),
      ],
      child: tables.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => InlineAlert(message: ApiError.from(e).message),
        data: (items) => AppSelect<String?>(
          label: 'Table',
          value: _tableId,
          items: [
            for (final table in items)
              if (table.isFree) AppSelectItem<String?>(table.id, table.name),
          ],
          onChanged: (v) => setState(() => _tableId = v),
        ),
      ),
    );
  }
}
