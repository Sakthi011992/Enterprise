import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/api_error.dart';
import '../../../../core/auth/permission_keys.dart';
import '../../../../core/auth/session.dart';
import '../../../../core/auth/session_controller.dart';
import '../../../../core/ui/ui.dart';
import '../../data/pos_models.dart';
import '../../data/pos_repository.dart';
import '../pos_format.dart';
import 'dialog_frame.dart';
import 'manager_pin_dialog.dart';

/// Reasons offered for a void. One must be picked.
const voidReasons = ['Wrong item served', 'Guest changed mind (not served)', 'Spilled / broken'];

/// Voids selected items. Resolves to the updated order, or null when dismissed.
Future<OrderView?> showVoidDialog(BuildContext context, {required OrderView order}) {
  return showDialog<OrderView>(
    context: context,
    builder: (_) => VoidDialog(order: order),
  );
}

class VoidDialog extends ConsumerStatefulWidget {
  const VoidDialog({super.key, required this.order});

  final OrderView order;

  @override
  ConsumerState<VoidDialog> createState() => _VoidDialogState();
}

class _VoidDialogState extends ConsumerState<VoidDialog> {
  final Set<String> _selected = {};
  String? _reason;
  bool _busy = false;
  String? _error;

  List<OrderItemView> get _items => widget.order.liveItems;

  List<OrderItemView> get _chosen => [
        for (final i in _items)
          if (_selected.contains(i.id)) i,
      ];

  num get _chosenTotal => _chosen.fold<num>(0, (sum, i) => sum + i.totalValue);

  bool get _anySent => _chosen.any((i) => i.isSent);

  Future<void> _submit({required bool needsApproval}) async {
    if (_chosen.isEmpty) {
      setState(() => _error = 'Pick the items to void.');
      return;
    }
    if (_reason == null) {
      setState(() => _error = 'Pick a reason.');
      return;
    }
    final itemIds = _chosen.map((i) => i.id).toList();
    final reason = _reason!;

    if (needsApproval) {
      final approval = await showManagerPinDialog(
        context,
        type: ApprovalTypes.void_,
        orderId: widget.order.id,
        payload: {'itemIds': itemIds, 'reason': reason},
        reason: reason,
        title: 'Manager approves the void',
      );
      if (!mounted || approval == null || !approval.isApproved) return;
      await _send(itemIds, reason, approval.id);
      return;
    }
    await _send(itemIds, reason, null);
  }

  Future<void> _send(List<String> itemIds, String reason, String? approvalId) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final order = await ref.read(posRepositoryProvider).voidItems(
            widget.order.id,
            itemIds: itemIds,
            reason: reason,
            approvalId: approvalId,
          );
      if (!mounted) return;
      Navigator.of(context).pop(order);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = ApiError.from(e).message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final session = ref.watch(sessionProvider.select((s) => s.session));
    final level = session?.levelOf(Perm.salesVoid) ?? AccessLevel.none;
    final needsApproval = !level.atLeast(AccessLevel.approve);

    return PosDialogFrame(
      title: 'Void items',
      subtitle: 'Order ${widget.order.orderNumber}',
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Void ${formatRupees(_chosenTotal, alwaysPaise: true)}',
          variant: AppButtonVariant.danger,
          loading: _busy,
          onPressed: _busy ? null : () => _submit(needsApproval: needsApproval),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (needsApproval)
            Padding(
              padding: EdgeInsets.only(bottom: t.spacing.sm),
              child: const AppBanner(
                tone: StatusTone.warning,
                message: 'Voids need a manager. You will be asked for the manager PIN.',
              ),
            ),
          for (final item in _items)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(item.name),
              subtitle: Text(
                [
                  if (item.variantName != null) item.variantName!,
                  if (item.isSent) (item.ticketKind == 'BOT' ? 'BOT sent' : 'KOT sent'),
                ].join(' · '),
              ),
              secondary: Text(formatWire(item.total)),
              value: _selected.contains(item.id),
              onChanged: _busy
                  ? null
                  : (v) => setState(() {
                        if (v == true) {
                          _selected.add(item.id);
                        } else {
                          _selected.remove(item.id);
                        }
                        _error = null;
                      }),
            ),
          SizedBox(height: t.spacing.md),
          Text('Reason (required)', style: TextStyle(color: t.color.content.secondary)),
          SizedBox(height: t.spacing.xs),
          Wrap(
            spacing: t.spacing.sm,
            runSpacing: t.spacing.sm,
            children: [
              for (final r in voidReasons)
                PosChoiceChip(
                  label: r,
                  selected: _reason == r,
                  onTap: _busy ? null : () => setState(() => _reason = r),
                ),
            ],
          ),
          if (_anySent) ...[
            SizedBox(height: t.spacing.md),
            const AppBanner(
              tone: StatusTone.warning,
              message: 'The drink was already sent to the bar. A cancellation ticket will '
                  'print there, and the stock is logged as wastage.',
            ),
          ],
          if (_error != null) ...[
            SizedBox(height: t.spacing.sm),
            InlineAlert(message: _error!),
          ],
        ],
      ),
    );
  }
}
