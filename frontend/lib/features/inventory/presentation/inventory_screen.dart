import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/auth/permission_keys.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/ui/ui.dart';
import '../../pos/presentation/pos_format.dart';
import '../data/inventory_models.dart';
import '../data/inventory_repository.dart';
import 'log_wastage_sheet.dart';
import 'tabs/kegs_tab.dart';
import 'tabs/locations_tab.dart';
import 'tabs/stock_counts_tab.dart';
import 'tabs/stock_items_tab.dart';
import 'tabs/transfers_tab.dart';
import 'tabs/variance_tab.dart';
import 'tabs/wastage_tab.dart';

/// Menu & stock > Inventory (Inventory board). KPI tiles on top, then seven
/// tabs. Each tab is its own file under `tabs/`.
class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 7, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _logWastage() async {
    final saved = await showLogWastageSheet(context);
    if (saved && mounted) {
      ref.invalidate(wastageProvider);
      ref.invalidate(inventorySummaryProvider);
      showAppToast(context, 'Wastage logged');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final canCount = can(ref, Perm.stockCount, AccessLevel.edit);
    final summary = ref.watch(inventorySummaryProvider);

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(t.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Inventory',
              breadcrumb: 'Menu & stock',
              actions: [
                if (canCount)
                  AppButton(
                    label: 'Start stock count',
                    icon: Icons.fact_check_outlined,
                    onPressed: () => context.go('/stock-count'),
                  ),
                if (canCount)
                  AppButton(
                    label: 'Log wastage',
                    icon: Icons.delete_sweep_outlined,
                    onPressed: _logWastage,
                  ),
                if (canCount)
                  AppButton(
                    label: 'Transfer',
                    icon: Icons.swap_horiz,
                    onPressed: () async {
                      final saved = await showTransferDialog(context);
                      if (saved == true && mounted) {
                        ref.invalidate(transfersProvider);
                        ref.invalidate(inventorySummaryProvider);
                      }
                    },
                  ),
                if (canCount)
                  AppButton(
                    label: 'New stock item',
                    icon: Icons.add,
                    variant: AppButtonVariant.primary,
                    onPressed: () => context.go('/inventory/items/new'),
                  ),
              ],
            ),
            SizedBox(height: t.spacing.sm),
            summary.when(
              loading: () => SizedBox(height: 72, child: DelayedSkeleton(child: SkeletonList(rows: 1))),
              error: (e, _) => InlineAlert(message: ApiError.from(e).message),
              data: (s) => Wrap(
                spacing: t.spacing.md,
                runSpacing: t.spacing.sm,
                children: [
                  _Kpi(label: 'Stock value', value: formatWire(s.stockValue)),
                  _Kpi(label: 'Pour cost (7 days)', value: '${s.pourPercent}%'),
                  _Kpi(
                    label: 'Liquor variance (7 days)',
                    value: formatWire(s.liquorVarianceValue),
                  ),
                  _Kpi(label: 'Below par', value: '${s.belowParCount} items'),
                ],
              ),
            ),
            SizedBox(height: t.spacing.sm),
            TabBar(
              controller: _tabs,
              isScrollable: true,
              tabs: const [
                Tab(text: 'Stock items'),
                Tab(text: 'Locations'),
                Tab(text: 'Transfers'),
                Tab(text: 'Stock counts'),
                Tab(text: 'Wastage'),
                Tab(text: 'Variance report'),
                Tab(text: 'Kegs & empties'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: const [
                  StockItemsTab(),
                  LocationsTab(),
                  TransfersTab(),
                  StockCountsTab(),
                  WastageTab(),
                  VarianceTab(),
                  KegsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 180),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            SizedBox(height: t.spacing.xs),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
          ],
        ),
      ),
    );
  }
}
