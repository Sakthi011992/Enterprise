import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/auth/permission_keys.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/ui/ui.dart';
import '../../inventory/domain/periods.dart';
import '../../inventory/presentation/inventory_messages.dart';
import '../../pos/presentation/pos_format.dart';
import '../data/procurement_models.dart';
import '../data/procurement_repository.dart';
import 'tabs/debit_notes_tab.dart';
import 'tabs/vendors_tab.dart';

/// Menu & stock > Procurement (Procurement board). Purchase orders, goods
/// received, vendors and debit notes.
class ProcurementScreen extends ConsumerStatefulWidget {
  const ProcurementScreen({super.key});

  @override
  ConsumerState<ProcurementScreen> createState() => _ProcurementScreenState();
}

class _ProcurementScreenState extends ConsumerState<ProcurementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final canRequest = can(ref, Perm.stockPurchaseOrders, AccessLevel.request);
    final reorder = ref.watch(reorderSuggestionsProvider(null));
    final suggestions = reorder.valueOrNull?.length;

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(t.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Procurement',
              breadcrumb: 'Menu & stock',
              actions: [
                if (canRequest)
                  AppButton(
                    label: suggestions == null
                        ? 'Reorder suggestions'
                        : 'Reorder suggestions ($suggestions)',
                    icon: Icons.replay,
                    onPressed: () => context.go('/procurement/reorder'),
                  ),
                if (canRequest)
                  AppButton(
                    label: 'New purchase order',
                    icon: Icons.add,
                    variant: AppButtonVariant.primary,
                    onPressed: () => context.go('/procurement/po/new'),
                  ),
              ],
            ),
            SizedBox(height: t.spacing.sm),
            TabBar(
              controller: _tabs,
              isScrollable: true,
              tabs: const [
                Tab(text: 'Purchase orders'),
                Tab(text: 'Goods received (GRN)'),
                Tab(text: 'Vendors'),
                Tab(text: 'Debit notes'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: const [
                  _PurchaseOrdersTab(),
                  _GoodsReceivedTab(),
                  VendorsTab(),
                  DebitNotesTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Purchase orders with status count chips. Receive opens a GRN against the PO.
class _PurchaseOrdersTab extends ConsumerStatefulWidget {
  const _PurchaseOrdersTab();

  @override
  ConsumerState<_PurchaseOrdersTab> createState() => _PurchaseOrdersTabState();
}

class _PurchaseOrdersTabState extends ConsumerState<_PurchaseOrdersTab> {
  String? _status;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final canReceive = can(ref, Perm.stockPurchaseOrders, AccessLevel.request);
    final async = ref.watch(purchaseOrdersProvider(_status));
    final page = async.valueOrNull;
    final counts = page?.counts ?? const <String, int>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: t.spacing.sm,
          runSpacing: t.spacing.sm,
          children: [
            ChoiceChip(
              label: const Text('All statuses'),
              selected: _status == null,
              onSelected: (_) => setState(() => _status = null),
            ),
            for (final s in const [
              PoStatus.draft,
              PoStatus.sent,
              PoStatus.partlyReceived,
              PoStatus.invoiceMismatch,
              PoStatus.received,
            ])
              ChoiceChip(
                label: Text('${PoStatus.label(s)} ${counts[s] ?? 0}'),
                selected: _status == s,
                onSelected: (_) => setState(() => _status = s),
              ),
          ],
        ),
        SizedBox(height: t.spacing.sm),
        Expanded(
          child: AppDataTable<PoSummary>(
            columns: [
              AppColumn<PoSummary>(label: 'PO', cell: (r) => Text(r.number)),
              AppColumn<PoSummary>(label: 'Vendor', cell: (r) => Text(r.vendor?.name ?? '-')),
              AppColumn<PoSummary>(label: 'Deliver to', cell: (r) => Text(r.location?.name ?? '-')),
              AppColumn<PoSummary>(
                label: 'Amount',
                numeric: true,
                cell: (r) => Text(formatWire(r.total)),
              ),
              AppColumn<PoSummary>(label: 'Due', cell: (r) => Text(shortDay(r.dueDate))),
              AppColumn<PoSummary>(
                label: 'Status',
                cell: (r) => StatusBadge(label: PoStatus.label(r.status), tone: _poTone(r.status)),
              ),
              AppColumn<PoSummary>(
                label: 'Actions',
                cell: (r) => _poAction(context, r, canReceive),
              ),
            ],
            rows: page?.items ?? const <PoSummary>[],
            loading: async.isLoading && !async.hasValue,
            error: async.hasError && !async.hasValue ? ApiError.from(async.error!).message : null,
            onRetry: () => ref.invalidate(purchaseOrdersProvider(_status)),
            onRowTap: (r) => context.go('/procurement/po/${r.id}'),
            empty: const EmptyState(
              title: 'No purchase orders',
              message: 'Create one, or request a reorder from the items below par.',
              icon: Icons.local_shipping_outlined,
            ),
          ),
        ),
      ],
    );
  }

  static StatusTone _poTone(String status) => switch (status) {
        PoStatus.received => StatusTone.success,
        PoStatus.invoiceMismatch => StatusTone.danger,
        PoStatus.partlyReceived => StatusTone.warning,
        PoStatus.sent => StatusTone.info,
        PoStatus.cancelled => StatusTone.neutral,
        _ => StatusTone.neutral,
      };

  Widget _poAction(BuildContext context, PoSummary po, bool canReceive) {
    if (!canReceive) return const SizedBox.shrink();
    switch (po.status) {
      case PoStatus.sent:
        return AppButton(
          label: 'Receive',
          size: AppControlSize.sm,
          onPressed: () => context.go('/procurement/grn/new?poId=${po.id}'),
        );
      case PoStatus.partlyReceived:
        return AppButton(
          label: 'Receive rest',
          size: AppControlSize.sm,
          onPressed: () => context.go('/procurement/grn/new?poId=${po.id}'),
        );
      case PoStatus.invoiceMismatch:
        return AppButton(
          label: 'Resolve',
          size: AppControlSize.sm,
          onPressed: () => context.go('/procurement/po/${po.id}'),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

/// Goods received notes. Row tap opens the GRN.
class _GoodsReceivedTab extends ConsumerWidget {
  const _GoodsReceivedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(goodsReceivedProvider);
    return AppDataTable<GrnSummary>(
      columns: [
        AppColumn<GrnSummary>(label: 'GRN', cell: (r) => Text(r.number)),
        AppColumn<GrnSummary>(label: 'PO', cell: (r) => Text(r.poNumber ?? '-')),
        AppColumn<GrnSummary>(label: 'Vendor', cell: (r) => Text(r.vendor?.name ?? '-')),
        AppColumn<GrnSummary>(label: 'Into', cell: (r) => Text(r.location?.name ?? '-')),
        AppColumn<GrnSummary>(label: 'Received', cell: (r) => Text(shortDay(r.receivedOn))),
        AppColumn<GrnSummary>(
          label: 'Invoice',
          numeric: true,
          cell: (r) => Text(formatWire(r.invoiceValue)),
        ),
        AppColumn<GrnSummary>(
          label: 'Payable',
          numeric: true,
          cell: (r) => Text(formatWire(r.payable)),
        ),
        AppColumn<GrnSummary>(
          label: 'Status',
          cell: (r) => StatusBadge(
            label: r.mismatch
                ? 'Mismatch'
                : (r.status == GrnStatuses.draft ? 'Draft' : 'Posted'),
            tone: r.mismatch
                ? StatusTone.danger
                : (r.status == GrnStatuses.draft ? StatusTone.neutral : StatusTone.success),
          ),
        ),
      ],
      rows: async.valueOrNull ?? const <GrnSummary>[],
      loading: async.isLoading && !async.hasValue,
      error: async.hasError && !async.hasValue ? ApiError.from(async.error!).message : null,
      onRetry: () => ref.invalidate(goodsReceivedProvider),
      onRowTap: (r) => context.go('/procurement/grn/${r.id}'),
      empty: const EmptyState(
        title: 'Nothing received yet',
        message: 'Receive a delivery against a sent purchase order.',
        icon: Icons.inventory_outlined,
      ),
    );
  }
}
