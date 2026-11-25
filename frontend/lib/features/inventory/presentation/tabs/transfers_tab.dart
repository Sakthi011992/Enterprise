import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/api_error.dart';
import '../../../../core/auth/permission_keys.dart';
import '../../../../core/auth/permissions.dart';
import '../../../../core/auth/session.dart';
import '../../../../core/ui/ui.dart';
import '../../data/inventory_models.dart';
import '../../data/inventory_repository.dart';
import '../../domain/periods.dart';
import '../inventory_messages.dart';

/// Transfers of the last seven days, newest first.
final transfersProvider = FutureProvider<List<TransferView>>(
  (ref) => ref.watch(inventoryRepositoryProvider).transfers(
        from: daysAgoWire(6),
        to: todayWire(),
      ),
);

/// Opens the transfer dialog. Resolves to true when a transfer was saved.
Future<bool?> showTransferDialog(BuildContext context) =>
    showDialog<bool>(context: context, builder: (_) => const _TransferDialog());

/// Inventory > Transfers. Moving stock between locations (for example Cellar
/// to Bar). Quantities are base units, as everywhere in stock.
class TransfersTab extends ConsumerWidget {
  const TransfersTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final canEdit = can(ref, Perm.stockCount, AccessLevel.edit);
    final async = ref.watch(transfersProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Last 7 days. Each transfer moves stock out of one location and into another.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (canEdit)
              AppButton(
                label: 'New transfer',
                icon: Icons.swap_horiz,
                variant: AppButtonVariant.primary,
                onPressed: () async {
                  final saved = await showTransferDialog(context);
                  if (saved == true) ref.invalidate(transfersProvider);
                },
              ),
          ],
        ),
        SizedBox(height: t.spacing.sm),
        Expanded(
          child: AppDataTable<TransferView>(
            columns: [
              AppColumn<TransferView>(label: 'Number', cell: (r) => Text(r.number)),
              AppColumn<TransferView>(label: 'From', cell: (r) => Text(r.fromLocation?.name ?? '-')),
              AppColumn<TransferView>(label: 'To', cell: (r) => Text(r.toLocation?.name ?? '-')),
              AppColumn<TransferView>(label: 'Items', numeric: true, cell: (r) => Text('${r.lines.length}')),
              AppColumn<TransferView>(
                label: 'Lines',
                cell: (r) => Text(
                  r.lines.map((l) => '${l.name} ${l.qtyDisplay}').join(' · '),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AppColumn<TransferView>(label: 'By', cell: (r) => Text(r.createdBy?.name ?? '-')),
            ],
            rows: async.valueOrNull ?? const <TransferView>[],
            loading: async.isLoading && !async.hasValue,
            error: async.hasError && !async.hasValue ? ApiError.from(async.error!).message : null,
            onRetry: () => ref.invalidate(transfersProvider),
            empty: const EmptyState(
              title: 'No transfers in the last 7 days',
              message: 'Move stock from the cellar to the bar here.',
              icon: Icons.swap_horiz,
            ),
          ),
        ),
      ],
    );
  }
}

class _TLine {
  _TLine() : qty = TextEditingController(text: '');

  String? stockItemId;
  final TextEditingController qty;

  void dispose() => qty.dispose();
}

class _TransferDialog extends ConsumerStatefulWidget {
  const _TransferDialog();

  @override
  ConsumerState<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends ConsumerState<_TransferDialog> {
  String? _from;
  String? _to;
  final _note = TextEditingController();
  final _lines = <_TLine>[_TLine()];
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final picked = [
      for (final l in _lines)
        if (l.stockItemId != null && (num.tryParse(l.qty.text.trim()) ?? 0) > 0)
          (stockItemId: l.stockItemId!, qty: num.parse(l.qty.text.trim())),
    ];
    if (_from == null || _to == null) {
      setState(() => _error = 'Pick both locations.');
      return;
    }
    if (_from == _to) {
      setState(() => _error = 'Choose two different locations.');
      return;
    }
    if (picked.isEmpty) {
      setState(() => _error = 'Add at least one item with a quantity above zero.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(inventoryRepositoryProvider).createTransfer(
            fromLocationId: _from!,
            toLocationId: _to!,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            lines: picked,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = inventoryErrorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final locations = ref.watch(inventoryLocationsProvider).valueOrNull ?? const <LocationView>[];
    final items = _from == null
        ? const <StockItemRow>[]
        : ref
                .watch(stockItemsProvider((locationId: _from, status: null, liquor: false)))
                .valueOrNull ??
            const <StockItemRow>[];

    return AlertDialog(
      title: const Text('New transfer'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                InlineAlert(message: _error!),
                SizedBox(height: t.spacing.sm),
              ],
              AppSelect<String>(
                label: 'From',
                value: _from,
                items: [for (final l in locations) AppSelectItem(l.id, l.name)],
                onChanged: (v) => setState(() {
                  _from = v;
                  for (final l in _lines) {
                    l.stockItemId = null;
                  }
                }),
              ),
              SizedBox(height: t.spacing.md),
              AppSelect<String>(
                label: 'To',
                value: _to,
                items: [for (final l in locations) AppSelectItem(l.id, l.name)],
                onChanged: (v) => setState(() => _to = v),
              ),
              SizedBox(height: t.spacing.md),
              for (var i = 0; i < _lines.length; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: t.spacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: AppSelect<String>(
                          label: 'Item ${i + 1}',
                          value: _lines[i].stockItemId,
                          items: [for (final s in items) AppSelectItem(s.id, s.name)],
                          onChanged: (v) => setState(() => _lines[i].stockItemId = v),
                        ),
                      ),
                      SizedBox(width: t.spacing.sm),
                      Expanded(
                        flex: 2,
                        child: AppTextField(
                          label: 'Qty (base units)',
                          controller: _lines[i].qty,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                ),
              AppButton(
                label: 'Add item',
                icon: Icons.add,
                size: AppControlSize.sm,
                onPressed: () => setState(() => _lines.add(_TLine())),
              ),
              SizedBox(height: t.spacing.md),
              AppTextField(label: 'Note (optional)', controller: _note),
            ],
          ),
        ),
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: 'Transfer',
          variant: AppButtonVariant.primary,
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}
