import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/api_error.dart';
import '../../../../core/ui/ui.dart';
import '../../data/inventory_models.dart';
import '../../data/inventory_repository.dart';

/// Keg stock: full kegs in each location, and how much is on tap now.
final kegsProvider = FutureProvider<List<KegRow>>(
  (ref) => ref.watch(inventoryRepositoryProvider).kegs(),
);

/// Inventory > Kegs & empties. Empties and deposits are not tracked yet.
class KegsTab extends ConsumerWidget {
  const KegsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final async = ref.watch(kegsProvider);

    return async.when(
      loading: () => DelayedSkeleton(child: SkeletonList()),
      error: (e, _) => ErrorState(
        message: ApiError.from(e).message,
        onRetry: () => ref.invalidate(kegsProvider),
      ),
      data: (kegs) {
        if (kegs.isEmpty) {
          return const EmptyState(
            title: 'No kegs yet',
            message: 'Items marked as keg show up here with the amount on tap.',
            icon: Icons.sports_bar_outlined,
          );
        }
        return SingleChildScrollView(
          child: Wrap(
            spacing: t.spacing.md,
            runSpacing: t.spacing.md,
            children: [
              for (final k in kegs)
                SizedBox(
                  width: 340,
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(k.name, style: Theme.of(context).textTheme.titleMedium),
                        SizedBox(height: t.spacing.xs),
                        Text('${k.fullKegs} full kegs'),
                        Text('On tap: ${k.onTapDisplay}'),
                        SizedBox(height: t.spacing.sm),
                        for (final l in k.locationBreakdown)
                          Text('${l.name}: ${l.qtyDisplay}',
                              style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
