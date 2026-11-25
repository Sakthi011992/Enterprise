import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/api_error.dart';
import '../../../../core/ui/ui.dart';
import '../../../pos/presentation/pos_format.dart';
import '../../data/inventory_models.dart';
import '../../data/inventory_repository.dart';
import '../widgets/stock_status_badge.dart';

/// Inventory > Stock items: location filter, status chips, search, and the
/// table from the Inventory board. Row tap opens the editor.
class StockItemsTab extends ConsumerStatefulWidget {
  const StockItemsTab({super.key});

  @override
  ConsumerState<StockItemsTab> createState() => _StockItemsTabState();
}

class _StockItemsTabState extends ConsumerState<StockItemsTab> {
  static const _statuses = <(String?, String)>[
    (null, 'All'),
    (StockStatus.belowPar, 'Below par'),
    (StockStatus.expires, 'Expiring'),
    (StockStatus.variance, 'Variance'),
    (StockStatus.negative, 'Negative'),
  ];

  String? _locationId;
  String? _status;
  bool _liquor = false;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final locations = ref.watch(inventoryLocationsProvider).valueOrNull ?? const <LocationView>[];
    final filter = (locationId: _locationId, status: _status, liquor: _liquor);
    final async = ref.watch(stockItemsProvider(filter));
    final search = _search.toLowerCase();
    final rows = [
      for (final r in async.valueOrNull ?? const <StockItemRow>[])
        if (search.isEmpty || r.name.toLowerCase().contains(search)) r,
    ];

    var locationName = 'All locations';
    for (final l in locations) {
      if (l.id == _locationId) locationName = l.name;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: t.spacing.md,
          runSpacing: t.spacing.sm,
          children: [
            SizedBox(
              width: 240,
              child: AppSelect<String>(
                label: 'Location',
                value: _locationId ?? '',
                items: [
                  const AppSelectItem('', 'All locations'),
                  for (final l in locations) AppSelectItem(l.id, l.name),
                ],
                onChanged: (v) => setState(() => _locationId = (v == null || v.isEmpty) ? null : v),
              ),
            ),
            for (final (value, label) in _statuses)
              ChoiceChip(
                label: Text(label),
                selected: _status == value,
                onSelected: (_) => setState(() => _status = value),
              ),
            FilterChip(
              label: const Text('Liquor'),
              selected: _liquor,
              onSelected: (v) => setState(() => _liquor = v),
            ),
          ],
        ),
        SizedBox(height: t.spacing.sm),
        Expanded(
          child: AppDataTable<StockItemRow>(
            columns: [
              AppColumn<StockItemRow>(label: 'Item', cell: (r) => Text(r.name, overflow: TextOverflow.ellipsis)),
              AppColumn<StockItemRow>(label: 'Location', cell: (_) => Text(locationName)),
              AppColumn<StockItemRow>(label: 'On hand', cell: (r) => Text(r.onHandDisplay)),
              AppColumn<StockItemRow>(label: 'Par', cell: (r) => Text(r.parDisplay)),
              AppColumn<StockItemRow>(label: 'Unit cost', cell: (r) => Text(r.unitCostDisplay)),
              AppColumn<StockItemRow>(
                label: 'Value',
                numeric: true,
                cell: (r) => Text(formatWire(r.value)),
              ),
              AppColumn<StockItemRow>(label: 'Status', cell: (r) => StockStatusBadge(status: r.status)),
            ],
            rows: rows,
            searchHint: 'Search items',
            onSearch: (v) => setState(() => _search = v),
            loading: async.isLoading && !async.hasValue,
            error: async.hasError && !async.hasValue ? ApiError.from(async.error!).message : null,
            onRetry: () => ref.invalidate(stockItemsProvider(filter)),
            onRowTap: (r) => context.go('/inventory/items/${r.id}'),
            empty: const EmptyState(
              title: 'No stock items match',
              message: 'Try another location or status, or add a new stock item.',
              icon: Icons.inventory_2_outlined,
            ),
          ),
        ),
      ],
    );
  }
}
