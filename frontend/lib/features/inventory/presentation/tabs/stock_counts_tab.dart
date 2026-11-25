import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/api_error.dart';
import '../../../../core/auth/permission_keys.dart';
import '../../../../core/auth/permissions.dart';
import '../../../../core/auth/session.dart';
import '../../../../core/ui/ui.dart';
import '../../data/inventory_models.dart';
import '../../data/inventory_repository.dart';

/// Every count, newest first. Open ones continue on the count screen.
final countsProvider = FutureProvider<List<CountSummary>>(
  (ref) => ref.watch(inventoryRepositoryProvider).counts(),
);

/// Inventory > Stock counts.
class StockCountsTab extends ConsumerWidget {
  const StockCountsTab({super.key});

  static String _status(String status) => switch (status) {
        CountStatus.submitted => 'Submitted',
        CountStatus.posted => 'Posted',
        CountStatus.cancelled => 'Cancelled',
        _ => 'Open',
      };

  static StatusTone _tone(String status) => switch (status) {
        CountStatus.submitted => StatusTone.info,
        CountStatus.posted => StatusTone.success,
        CountStatus.cancelled => StatusTone.neutral,
        _ => StatusTone.warning,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final canCount = can(ref, Perm.stockCount, AccessLevel.edit);
    final async = ref.watch(countsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Open counts continue where you left off. Tap a count to see its lines.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (canCount)
              AppButton(
                label: 'Start stock count',
                icon: Icons.fact_check_outlined,
                variant: AppButtonVariant.primary,
                onPressed: () => context.go('/stock-count'),
              ),
          ],
        ),
        SizedBox(height: t.spacing.sm),
        Expanded(
          child: AppDataTable<CountSummary>(
            columns: [
              AppColumn<CountSummary>(label: 'Location', cell: (r) => Text(r.location?.name ?? '-')),
              AppColumn<CountSummary>(
                label: 'Status',
                cell: (r) => StatusBadge(label: _status(r.status), tone: _tone(r.status)),
              ),
              AppColumn<CountSummary>(
                label: 'Counted',
                cell: (r) => Text('${r.countedLines} of ${r.totalLines} items'),
              ),
              AppColumn<CountSummary>(label: 'Business date', cell: (r) => Text(r.businessDate)),
              AppColumn<CountSummary>(label: 'Started by', cell: (r) => Text(r.startedBy?.name ?? '-')),
            ],
            rows: async.valueOrNull ?? const <CountSummary>[],
            loading: async.isLoading && !async.hasValue,
            error: async.hasError && !async.hasValue ? ApiError.from(async.error!).message : null,
            onRetry: () => ref.invalidate(countsProvider),
            onRowTap: (r) => context.go('/stock-count?countId=${r.id}'),
            empty: const EmptyState(
              title: 'No counts yet',
              message: 'Start a count to check the shelves against the system.',
              icon: Icons.fact_check_outlined,
            ),
          ),
        ),
      ],
    );
  }
}
