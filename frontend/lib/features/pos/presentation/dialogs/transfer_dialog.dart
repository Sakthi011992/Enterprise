import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/api_error.dart';
import '../../../../core/ui/ui.dart';
import '../../data/pos_models.dart';
import '../../data/pos_repository.dart';
import '../pos_format.dart';
import '../pos_order_controller.dart';
import 'dialog_frame.dart';

enum TransferMode { wholeTable, someItems, merge }

/// Move the whole table, move some items to another table, or merge another open
/// order into this one. Resolves to the updated order, or null when dismissed.
Future<OrderView?> showTransferDialog(BuildContext context, {required OrderView order}) {
  return showDialog<OrderView>(
    context: context,
    builder: (_) => TransferDialog(order: order),
  );
}

/// Label for a table status on the grid.
String tableStatusLabel(String status) => switch (status) {
      'FREE' => 'Free',
      'OCCUPIED' => 'Occupied',
      'BILL_PRINTED' => 'Bill printed',
      'CLEANING' => 'Cleaning',
      'RESERVED' => 'Reserved',
      _ => status,
    };

/// Why a table cannot take this order, or null when it can.
String? tableBlockReason(TableView table, OrderView order, TransferMode mode) {
  if (table.mergedIntoId != null) return 'Merged';
  if (order.table?.id == table.id) return 'This table';
  if (!table.isFree) return tableStatusLabel(table.status);
  if (mode == TransferMode.wholeTable && !table.fits(order.covers)) return 'Too small';
  return null;
}

class TransferDialog extends ConsumerStatefulWidget {
  const TransferDialog({super.key, required this.order});

  final OrderView order;

  @override
  ConsumerState<TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends ConsumerState<TransferDialog> {
  late TransferMode _mode = widget.order.table != null ? TransferMode.wholeTable : TransferMode.someItems;
  String? _tableId;
  String? _mergeOrderId;
  final Set<String> _itemIds = {};
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    final repo = ref.read(posRepositoryProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final OrderView result = switch (_mode) {
        TransferMode.wholeTable => await repo.move(widget.order.id, toTableId: _tableId!),
        TransferMode.someItems => await repo.transferItems(
            widget.order.id,
            itemIds: _itemIds.toList(),
            toTableId: _tableId,
          ),
        TransferMode.merge => await repo.merge(widget.order.id, fromOrderId: _mergeOrderId!),
      };
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = ApiError.from(e).message;
      });
    }
  }

  String? get _problem {
    if (_mode == TransferMode.merge) {
      return _mergeOrderId == null ? 'Pick the order to merge in.' : null;
    }
    if (_tableId == null) return 'Pick a table.';
    if (_mode == TransferMode.someItems && _itemIds.isEmpty) return 'Pick the items to move.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final order = widget.order;
    final tables = ref.watch(posTablesProvider);

    return PosDialogFrame(
      title: 'Move or merge',
      subtitle: order.table == null
          ? 'Order ${order.orderNumber}'
          : 'Order ${order.orderNumber} · ${order.table!.name}',
      width: 640,
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: _actionLabel(),
          variant: AppButtonVariant.primary,
          loading: _busy,
          onPressed: (_busy || _problem != null) ? null : _submit,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: t.spacing.sm,
            runSpacing: t.spacing.sm,
            children: [
              if (order.table != null)
                PosChoiceChip(
                  label: 'Whole table',
                  selected: _mode == TransferMode.wholeTable,
                  onTap: _busy ? null : () => _setMode(TransferMode.wholeTable),
                ),
              PosChoiceChip(
                label: 'Some items',
                selected: _mode == TransferMode.someItems,
                onTap: _busy ? null : () => _setMode(TransferMode.someItems),
              ),
              PosChoiceChip(
                label: 'Merge',
                selected: _mode == TransferMode.merge,
                onTap: _busy ? null : () => _setMode(TransferMode.merge),
              ),
            ],
          ),
          SizedBox(height: t.spacing.md),
          if (_mode == TransferMode.someItems) ...[
            for (final item in order.liveItems)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(item.name),
                subtitle: Text(item.isSent ? 'Sent to the kitchen or bar' : 'Not sent yet'),
                secondary: Text(formatWire(item.total)),
                value: _itemIds.contains(item.id),
                onChanged: _busy
                    ? null
                    : (v) => setState(() {
                          if (v == true) {
                            _itemIds.add(item.id);
                          } else {
                            _itemIds.remove(item.id);
                          }
                        }),
              ),
            SizedBox(height: t.spacing.md),
          ],
          if (_mode == TransferMode.merge)
            _MergeList(
              currentOrderId: order.id,
              selectedId: _mergeOrderId,
              onPick: (id) => setState(() => _mergeOrderId = id),
            )
          else
            tables.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => InlineAlert(message: ApiError.from(e).message),
              data: (all) => _TableGrid(
                tables: [for (final table in all) if (table.mergedIntoId == null) table],
                order: order,
                mode: _mode,
                selectedId: _tableId,
                onPick: (id) => setState(() {
                  _tableId = id;
                  _error = null;
                }),
              ),
            ),
          if (_mode == TransferMode.wholeTable && _tooSmallWarning(tables.valueOrNull) != null) ...[
            SizedBox(height: t.spacing.md),
            InlineAlert(message: _tooSmallWarning(tables.valueOrNull)!),
          ],
          if (_error != null) ...[
            SizedBox(height: t.spacing.sm),
            InlineAlert(message: _error!),
          ],
        ],
      ),
    );
  }

  void _setMode(TransferMode mode) => setState(() {
        _mode = mode;
        _tableId = null;
        _mergeOrderId = null;
        _error = null;
      });

  String _actionLabel() {
    switch (_mode) {
      case TransferMode.wholeTable:
        return 'Move to ${_tableName() ?? 'table'}';
      case TransferMode.someItems:
        return 'Move ${_itemIds.length} item${_itemIds.length == 1 ? '' : 's'}';
      case TransferMode.merge:
        return 'Merge';
    }
  }

  String? _tableName() {
    final tables = ref.read(posTablesProvider).valueOrNull ?? const <TableView>[];
    for (final table in tables) {
      if (table.id == _tableId) return table.name;
    }
    return null;
  }

  /// The seat-size warning from the POSApprove board. Shown for the table the
  /// staff picked when it is too small for the guests.
  String? _tooSmallWarning(List<TableView>? tables) {
    if (tables == null || _tableId == null) return null;
    for (final table in tables) {
      if (table.id != _tableId) continue;
      if (table.fits(widget.order.covers)) return null;
      final from = widget.order.table?.name ?? 'this table';
      return '${table.name} has ${table.seats} seats but $from has '
          '${widget.order.covers} guests. Pick a bigger table.';
    }
    return null;
  }
}

class _TableGrid extends StatelessWidget {
  const _TableGrid({
    required this.tables,
    required this.order,
    required this.mode,
    required this.selectedId,
    required this.onPick,
  });

  final List<TableView> tables;
  final OrderView order;
  final TransferMode mode;
  final String? selectedId;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (tables.isEmpty) {
      return const EmptyState(title: 'No tables set up', icon: Icons.table_restaurant_outlined);
    }
    return Wrap(
      spacing: t.spacing.sm,
      runSpacing: t.spacing.sm,
      children: [
        for (final table in tables)
          _TableTile(
            table: table,
            blockedBy: tableBlockReason(table, order, mode),
            selected: table.id == selectedId,
            onTap: onPick,
          ),
      ],
    );
  }
}

class _TableTile extends StatelessWidget {
  const _TableTile({
    required this.table,
    required this.blockedBy,
    required this.selected,
    required this.onTap,
  });

  final TableView table;
  final String? blockedBy;
  final bool selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final enabled = blockedBy == null;
    final tone = table.isFree
        ? StatusTone.success
        : (table.status == 'CLEANING' ? StatusTone.neutral : StatusTone.warning);
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: '${table.name}, ${table.seats} seats, ${blockedBy ?? tableStatusLabel(table.status)}',
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Material(
          color: selected ? t.color.background.inverse : t.color.background.surface,
          borderRadius: BorderRadius.circular(t.radius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(t.radius.md),
            onTap: enabled ? () => onTap(table.id) : null,
            child: Container(
              width: 120,
              constraints: const BoxConstraints(minHeight: 64),
              padding: EdgeInsets.all(t.spacing.sm),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(t.radius.md),
                border: Border.all(
                  color: selected ? t.color.border.accent : t.color.border.default,
                  width: t.borderWidth.hairline,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    table.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: selected ? t.color.content.onInverse : t.color.content.primary,
                    ),
                  ),
                  Text(
                    '${table.seats} seats',
                    style: TextStyle(
                      fontSize: 12,
                      color: selected ? t.color.content.onInverse : t.color.content.secondary,
                    ),
                  ),
                  SizedBox(height: t.spacing.xs),
                  StatusBadge(label: blockedBy ?? tableStatusLabel(table.status), tone: tone),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MergeList extends ConsumerWidget {
  const _MergeList({required this.currentOrderId, required this.selectedId, required this.onPick});

  final String currentOrderId;
  final String? selectedId;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final open = ref.watch(openOrdersProvider);
    return open.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => InlineAlert(message: ApiError.from(e).message),
      data: (orders) {
        final others = [for (final o in orders) if (o.id != currentOrderId) o];
        if (others.isEmpty) {
          return const EmptyState(
            title: 'No other open orders',
            message: 'Open another order first, then merge it in here.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final o in others)
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: o.id,
                groupValue: selectedId,
                onChanged: (v) {
                  if (v != null) onPick(v);
                },
                title: Text(
                  [o.orderNumber, if (o.tableName != null) o.tableName!].join(' · '),
                ),
                subtitle: Text(
                  [
                    OrderTypes.label(o.type),
                    if (o.grandTotal != null) formatWire(o.grandTotal!),
                  ].join(' · '),
                  style: TextStyle(color: t.color.content.secondary),
                ),
              ),
          ],
        );
      },
    );
  }
}
