import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/api_error.dart';
import '../../../../core/auth/permission_keys.dart';
import '../../../../core/auth/permissions.dart';
import '../../../../core/auth/session.dart';
import '../../../../core/ui/ui.dart';
import '../../../inventory/presentation/inventory_messages.dart';
import '../../../pos/presentation/pos_format.dart';
import '../../data/procurement_models.dart';
import '../../data/procurement_repository.dart';

/// Procurement > Debit notes. Raised when a delivery is short or invoiced but
/// not received. Settling needs `stock.purchaseOrders` EDIT.
class DebitNotesTab extends ConsumerWidget {
  const DebitNotesTab({super.key});

  Future<void> _settle(BuildContext context, WidgetRef ref, DebitNoteView note) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Mark ${note.number} as settled?',
      message: 'Use this once the vendor has credited ${formatWire(note.amount)}.',
      confirmLabel: 'Mark settled',
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(procurementRepositoryProvider).settleDebitNote(note.id);
      ref.invalidate(debitNotesProvider);
      if (context.mounted) showAppToast(context, '${note.number} settled');
    } catch (e) {
      if (context.mounted) showAppToast(context, inventoryErrorText(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canEdit = can(ref, Perm.stockPurchaseOrders, AccessLevel.edit);
    final async = ref.watch(debitNotesProvider);

    return AppDataTable<DebitNoteView>(
      columns: [
        AppColumn<DebitNoteView>(label: 'Number', cell: (r) => Text(r.number)),
        AppColumn<DebitNoteView>(label: 'Vendor', cell: (r) => Text(r.vendor?.name ?? '-')),
        AppColumn<DebitNoteView>(label: 'From GRN', cell: (r) => Text(r.grnNumber ?? '-')),
        AppColumn<DebitNoteView>(
          label: 'Amount',
          numeric: true,
          cell: (r) => Text(formatWire(r.amount)),
        ),
        AppColumn<DebitNoteView>(
          label: 'Reason',
          cell: (r) => Text(r.reason, overflow: TextOverflow.ellipsis),
        ),
        AppColumn<DebitNoteView>(
          label: 'Status',
          cell: (r) => StatusBadge(
            label: r.status == DebitNoteStatuses.settled ? 'Settled' : 'Open',
            tone: r.status == DebitNoteStatuses.settled ? StatusTone.success : StatusTone.warning,
          ),
        ),
        AppColumn<DebitNoteView>(
          label: '',
          cell: (r) => r.status == DebitNoteStatuses.open && canEdit
              ? AppButton(
                  label: 'Mark settled',
                  size: AppControlSize.sm,
                  onPressed: () => _settle(context, ref, r),
                )
              : const SizedBox.shrink(),
        ),
      ],
      rows: async.valueOrNull ?? const <DebitNoteView>[],
      loading: async.isLoading && !async.hasValue,
      error: async.hasError && !async.hasValue ? ApiError.from(async.error!).message : null,
      onRetry: () => ref.invalidate(debitNotesProvider),
      empty: const EmptyState(
        title: 'No debit notes',
        message: 'A debit note appears when a delivery is invoiced but not received.',
        icon: Icons.receipt_outlined,
      ),
    );
  }
}
