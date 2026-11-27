import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/auth/permission_keys.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/ui/ui.dart';
import '../../guest_requests/presentation/floor_guest_widgets.dart';
import '../data/floor_repository.dart';
import '../domain/table_status.dart';

const _refreshEvery = Duration(seconds: 15);
const _tileWidth = 140.0;
const _tileHeight = 124.0;
const _panelWidth = 300.0;

const _legendStatuses = [
  TableStatus.free,
  TableStatus.occupied,
  TableStatus.billPrinted,
  TableStatus.cleaning,
  TableStatus.reserved,
];

/// Floor plan: the live table view for one area. Tapping a table opens a
/// panel with its order and, for an empty table, its status controls.
class FloorPlanScreen extends ConsumerStatefulWidget {
  const FloorPlanScreen({super.key});

  @override
  ConsumerState<FloorPlanScreen> createState() => _FloorPlanScreenState();
}

class _FloorPlanScreenState extends ConsumerState<FloorPlanScreen> {
  String? _areaId;
  String? _selectedId;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(_refreshEvery, (_) {
      if (mounted) ref.invalidate(floorTablesProvider);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _setStatus(FloorTable table, String status) async {
    setState(() => _error = null);
    try {
      await ref.read(floorRepositoryProvider).setTableStatus(table.id, status);
      ref.invalidate(floorTablesProvider);
    } catch (e) {
      if (mounted) setState(() => _error = ApiError.from(e).message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final areas = ref.watch(floorAreasProvider);
    final tables = ref.watch(floorTablesProvider);
    final canChangeStatus = can(ref, Perm.salesOrdersTake, AccessLevel.edit);
    final canEditLayout = can(ref, Perm.adminSettings, AccessLevel.view);

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(t.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Floor plan & tables',
              breadcrumb: 'Sales',
              actions: [
                AppButton(
                  label: 'Refresh',
                  icon: Icons.refresh,
                  variant: AppButtonVariant.ghost,
                  onPressed: () => ref.invalidate(floorTablesProvider),
                ),
                if (canEditLayout)
                  AppButton(
                    label: 'Edit layout',
                    icon: Icons.edit_outlined,
                    onPressed: () => context.go('/settings/floor'),
                  ),
              ],
            ),
            if (_error != null) ...[
              SizedBox(height: t.spacing.sm),
              InlineAlert(message: _error!),
            ],
            SizedBox(height: t.spacing.sm),
            Expanded(
              child: tables.when(
                skipLoadingOnReload: true,
                loading: () => DelayedSkeleton(child: SkeletonList()),
                error: (e, _) => ErrorState(
                  message: ApiError.from(e).message,
                  onRetry: () => ref.invalidate(floorTablesProvider),
                ),
                data: (list) => areas.when(
                  skipLoadingOnReload: true,
                  loading: () => DelayedSkeleton(child: SkeletonList()),
                  error: (e, _) => ErrorState(
                    message: ApiError.from(e).message,
                    onRetry: () => ref.invalidate(floorAreasProvider),
                  ),
                  data: (areaList) => _body(areaList, list, canChangeStatus),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(List<FloorArea> areas, List<FloorTable> tables, bool canChangeStatus) {
    final t = context.tokens;
    if (areas.isEmpty) {
      return EmptyState(
        title: 'No areas yet',
        message: 'Add an area and its tables in floor setup.',
        icon: Icons.table_restaurant_outlined,
        actionLabel: 'Open floor setup',
        onAction: () => context.go('/settings/floor'),
      );
    }
    final area = _areaById(areas, _areaId) ?? areas.first;
    final visible = [
      for (final table in tables)
        if (table.areaId == area.id && !table.isMerged) table,
    ];
    final selected = _tableById(tables, _selectedId);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: t.spacing.sm,
                runSpacing: t.spacing.sm,
                children: [
                  for (final a in areas)
                    ChoiceChip(
                      label: Text(a.name),
                      selected: a.id == area.id,
                      onSelected: (_) => setState(() {
                        _areaId = a.id;
                        _selectedId = null;
                      }),
                    ),
                ],
              ),
              SizedBox(height: t.spacing.sm),
              Wrap(
                spacing: t.spacing.sm,
                runSpacing: t.spacing.xs,
                children: [
                  for (final s in _legendStatuses)
                    StatusBadge(
                      label: tableStatusStyle(s).label,
                      tone: tableStatusStyle(s).tone,
                    ),
                ],
              ),
              SizedBox(height: t.spacing.md),
              Expanded(
                child: visible.isEmpty
                    ? EmptyState(
                        title: 'No tables in ${area.name}',
                        message: 'Tables you add in floor setup appear here.',
                        icon: Icons.table_restaurant_outlined,
                      )
                    : SingleChildScrollView(
                        child: Wrap(
                          spacing: t.spacing.md,
                          runSpacing: t.spacing.md,
                          children: [
                            for (final table in visible)
                              _TableTile(
                                table: table,
                                selected: table.id == _selectedId,
                                onTap: () => setState(() => _selectedId = table.id),
                              ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
        if (selected != null) ...[
          SizedBox(width: t.spacing.md),
          SizedBox(
            width: _panelWidth,
            child: _TablePanel(
              table: selected,
              canChangeStatus: canChangeStatus,
              onStatus: (status) => _setStatus(selected, status),
              onClose: () => setState(() => _selectedId = null),
            ),
          ),
        ],
      ],
    );
  }
}

FloorArea? _areaById(List<FloorArea> areas, String? id) {
  if (id == null) return null;
  for (final area in areas) {
    if (area.id == id) return area;
  }
  return null;
}

FloorTable? _tableById(List<FloorTable> tables, String? id) {
  if (id == null) return null;
  for (final table in tables) {
    if (table.id == id) return table;
  }
  return null;
}

class _TableTile extends StatelessWidget {
  const _TableTile({required this.table, required this.selected, required this.onTap});

  final FloorTable table;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final style = tableStatusStyle(table.status);
    final colors = toneColorsOf(context, style.tone);
    final order = table.order;
    final text = Theme.of(context).textTheme;
    final detail = order == null ? null : '${order.covers} covers · ₹${order.grandTotal}';

    return Semantics(
      button: true,
      selected: selected,
      label: '${table.name}, ${style.label}${detail == null ? '' : ', $detail'}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: _tileWidth,
          height: _tileHeight,
          padding: EdgeInsets.all(t.spacing.sm + 2),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? t.color.border.focus : colors.foreground,
              width: selected ? t.borderWidth.thick : t.borderWidth.hairline,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                table.name,
                style: text.titleMedium?.copyWith(color: colors.foreground, fontWeight: FontWeight.w700),
              ),
              Text(style.label, style: text.bodySmall?.copyWith(color: colors.foreground)),
              if (detail != null)
                Text(detail, style: text.bodySmall?.copyWith(color: colors.foreground)),
              TableGuestBadges(tableId: table.id, status: table.status),
            ],
          ),
        ),
      ),
    );
  }
}

class _TablePanel extends StatelessWidget {
  const _TablePanel({
    required this.table,
    required this.canChangeStatus,
    required this.onStatus,
    required this.onClose,
  });

  final FloorTable table;
  final bool canChangeStatus;
  final ValueChanged<String> onStatus;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final style = tableStatusStyle(table.status);
    final order = table.order;

    return AppCard(
      title: table.name,
      actions: [
        AppIconButton(icon: Icons.close, tooltip: 'Close panel', onPressed: onClose),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              StatusBadge(label: style.label, tone: style.tone),
              SizedBox(width: t.spacing.sm),
              Text('${table.seats} seats', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          SizedBox(height: t.spacing.md),
          if (order != null) ...[
            _Line(label: 'Order', value: order.orderNumber),
            _Line(label: 'Covers', value: '${order.covers}'),
            _Line(label: 'Total', value: '₹${order.grandTotal}'),
            if (order.waiterName != null) _Line(label: 'Waiter', value: order.waiterName!),
            if (order.openedAt != null)
              _Line(label: 'Opened', value: DateFormat.Hm().format(order.openedAt!.toLocal())),
            SizedBox(height: t.spacing.md),
            AppButton(
              label: 'Open bill',
              icon: Icons.receipt_long_outlined,
              variant: AppButtonVariant.primary,
              onPressed: () => context.go('/pos/${order.id}'),
            ),
          ] else ...[
            AppButton(
              label: 'Start order',
              icon: Icons.add,
              variant: AppButtonVariant.primary,
              onPressed: () => context.go('/pos?tableId=${table.id}'),
            ),
            if (canChangeStatus) ...[
              SizedBox(height: t.spacing.md),
              Text('Set status', style: Theme.of(context).textTheme.labelLarge),
              SizedBox(height: t.spacing.xs),
              Wrap(
                spacing: t.spacing.sm,
                runSpacing: t.spacing.xs,
                children: [
                  for (final s in manualTableStatuses)
                    AppButton(
                      label: tableStatusStyle(s).label,
                      size: AppControlSize.sm,
                      variant: s == table.status
                          ? AppButtonVariant.primary
                          : AppButtonVariant.secondary,
                      onPressed: s == table.status ? null : () => onStatus(s),
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.spacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
