import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/api_error.dart';
import '../../../../core/ui/ui.dart';
import '../../../pos/presentation/pos_format.dart';
import '../../data/inventory_models.dart';
import '../../data/inventory_repository.dart';
import '../../domain/periods.dart';

typedef VarianceQuery = ({String? locationId, String from, String to, bool liquor});

/// Variance report for a window (PLAN 1.3 formula, computed on the server).
final varianceProvider = FutureProvider.family<VarianceReport, VarianceQuery>(
  (ref, q) => ref.watch(inventoryRepositoryProvider).variance(
        locationId: q.locationId,
        from: q.from,
        to: q.to,
        liquor: q.liquor,
      ),
);

/// Inventory > Variance report. Opening + received - sold - wastage = expected,
/// compared with what was counted. The unaccounted amount is the loss to explain.
class VarianceTab extends ConsumerStatefulWidget {
  const VarianceTab({super.key});

  @override
  ConsumerState<VarianceTab> createState() => _VarianceTabState();
}

class _VarianceTabState extends ConsumerState<VarianceTab> {
  String? _locationId;
  bool _liquor = true;

  VarianceQuery get _query => (
        locationId: _locationId,
        from: daysAgoWire(6),
        to: todayWire(),
        liquor: _liquor,
      );

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final locations = ref.watch(inventoryLocationsProvider).valueOrNull ?? const <LocationView>[];
    final query = _query;
    final async = ref.watch(varianceProvider(query));
    final report = async.valueOrNull;

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
            FilterChip(
              label: const Text('Liquor only'),
              selected: _liquor,
              onSelected: (v) => setState(() => _liquor = v),
            ),
            if (report != null)
              Text(
                'Unaccounted ${formatWire(report.totalVarianceValue)} over the last 7 days',
                style: Theme.of(context).textTheme.titleMedium,
              ),
          ],
        ),
        SizedBox(height: t.spacing.xs),
        Text(
          'Expected = opening + received - sold - wastage. Counted comes from posted counts.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        SizedBox(height: t.spacing.sm),
        Expanded(
          child: AppDataTable<VarianceRow>(
            columns: [
              AppColumn<VarianceRow>(label: 'Item', cell: (r) => Text(r.name, overflow: TextOverflow.ellipsis)),
              AppColumn<VarianceRow>(label: 'Opening', cell: (r) => Text(r.openingDisplay)),
              AppColumn<VarianceRow>(label: 'Received', cell: (r) => Text(r.receivedDisplay)),
              AppColumn<VarianceRow>(label: 'Sold', cell: (r) => Text(r.soldDisplay)),
              AppColumn<VarianceRow>(label: 'Wastage', cell: (r) => Text(r.wastageDisplay)),
              AppColumn<VarianceRow>(label: 'Expected', cell: (r) => Text(r.expectedDisplay)),
              AppColumn<VarianceRow>(
                label: 'Counted',
                cell: (r) => Text(r.countedDisplay ?? 'Not counted'),
              ),
              AppColumn<VarianceRow>(
                label: 'Unaccounted',
                numeric: true,
                cell: (r) => Text('${r.varianceDisplay} · ${formatWire(r.varianceValue)}'),
              ),
            ],
            rows: report?.rows ?? const <VarianceRow>[],
            loading: async.isLoading && !async.hasValue,
            error: async.hasError && !async.hasValue ? ApiError.from(async.error!).message : null,
            onRetry: () => ref.invalidate(varianceProvider(query)),
            empty: const EmptyState(
              title: 'Nothing to reconcile',
              message: 'Variance appears once stock has moved and a count is posted.',
              icon: Icons.balance_outlined,
            ),
          ),
        ),
      ],
    );
  }
}
