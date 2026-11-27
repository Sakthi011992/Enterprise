import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/api_error.dart';
import '../../../../core/ui/ui.dart';
import '../../../pos/presentation/pos_format.dart';
import '../../data/inventory_models.dart';
import '../../data/inventory_repository.dart';
import '../../domain/periods.dart';
import '../widgets/ink_widgets.dart';

typedef WastageQuery = ({String from, String to, String? locationId});

/// Wastage entries for a window and location, with header totals.
final wastageProvider = FutureProvider.family<WastageList, WastageQuery>(
  (ref, q) => ref.watch(inventoryRepositoryProvider).wastage(
        from: q.from,
        to: q.to,
        locationId: q.locationId,
      ),
);

/// Inventory > Wastage. Today or the last seven days, by location.
class WastageTab extends ConsumerStatefulWidget {
  const WastageTab({super.key});

  @override
  ConsumerState<WastageTab> createState() => _WastageTabState();
}

class _WastageTabState extends ConsumerState<WastageTab> {
  int _days = 0;
  String? _locationId;

  WastageQuery get _query => (
        from: daysAgoWire(_days),
        to: todayWire(),
        locationId: _locationId,
      );

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final locations = ref.watch(inventoryLocationsProvider).valueOrNull ?? const <LocationView>[];
    final query = _query;
    final async = ref.watch(wastageProvider(query));
    final list = async.valueOrNull;

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
            FilterPill(
              label: 'Today',
              selected: _days == 0,
              onSelected: () => setState(() => _days = 0),
            ),
            FilterPill(
              label: 'Last 7 days',
              selected: _days == 6,
              onSelected: () => setState(() => _days = 6),
            ),
            if (list != null)
              Text(
                'Total ${formatWire(list.totalValue)} · ${list.items.length} entries',
                style: Theme.of(context).textTheme.titleMedium,
              ),
          ],
        ),
        SizedBox(height: t.spacing.sm),
        Expanded(
          child: AppDataTable<WastageView>(
            columns: [
              AppColumn<WastageView>(
                label: 'When',
                cell: (r) => Text(_when(r.createdAt)),
              ),
              AppColumn<WastageView>(label: 'Item', cell: (r) => Text(r.stockItem?.name ?? '-')),
              AppColumn<WastageView>(label: 'Location', cell: (r) => Text(r.location?.name ?? '-')),
              AppColumn<WastageView>(label: 'Qty', cell: (r) => Text(r.qtyDisplay)),
              AppColumn<WastageView>(label: 'Reason', cell: (r) => Text(WastageReasons.label(r.reason))),
              AppColumn<WastageView>(
                label: 'Value',
                numeric: true,
                cell: (r) => Text(formatWire(r.value)),
              ),
              AppColumn<WastageView>(label: 'By', cell: (r) => Text(r.createdBy?.name ?? '-')),
              AppColumn<WastageView>(
                label: 'Photo',
                cell: (r) => Text(r.photoUrl == null ? '-' : 'Yes'),
              ),
            ],
            rows: list?.items ?? const <WastageView>[],
            loading: async.isLoading && !async.hasValue,
            error: async.hasError && !async.hasValue ? ApiError.from(async.error!).message : null,
            onRetry: () => ref.invalidate(wastageProvider(query)),
            empty: const EmptyState(
              title: 'No wastage logged',
              message: 'Broken glasses, spills and comps show up here once logged.',
              icon: Icons.delete_sweep_outlined,
            ),
          ),
        ),
      ],
    );
  }

  static String _when(DateTime? at) {
    if (at == null) return '-';
    final local = at.toLocal();
    return '${formatClock(local)} · ${local.day}/${local.month}';
  }
}
