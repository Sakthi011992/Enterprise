import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';
import '../data/guest_models.dart';

/// What the waiter chose in the Edit & confirm sheet.
sealed class EditConfirmResult {
  const EditConfirmResult();
}

/// Confirm with [items]. [edited] is false when nothing changed, so the
/// caller can confirm "as placed" without sending items.
class EditConfirmConfirmed extends EditConfirmResult {
  const EditConfirmConfirmed({required this.items, required this.edited});
  final List<GuestLine> items;
  final bool edited;
}

/// "Reject with reason" was tapped; the caller asks for the reason.
class EditConfirmRejected extends EditConfirmResult {
  const EditConfirmRejected();
}

const _maxQty = 99;

Future<EditConfirmResult?> showEditConfirmSheet(
  BuildContext context, {
  required GuestRequest request,
}) =>
    showModalBottomSheet<EditConfirmResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => EditConfirmSheet(request: request),
    );

/// Design: "Waiter · Edit & confirm". Quantity steppers, remove a line, an ID
/// note when the round has alcohol, the round total, Confirm & send and
/// Reject with reason.
class EditConfirmSheet extends StatefulWidget {
  const EditConfirmSheet({super.key, required this.request});

  final GuestRequest request;

  @override
  State<EditConfirmSheet> createState() => _EditConfirmSheetState();
}

class _EditConfirmSheetState extends State<EditConfirmSheet> {
  late List<GuestLine> _lines = List.of(widget.request.lines);
  bool _edited = false;

  void _setQty(int i, int qty) => setState(() {
        _lines[i] = _lines[i].copyWith(quantity: qty.clamp(1, _maxQty));
        _edited = true;
      });

  void _remove(int i) => setState(() {
        _lines = [..._lines]..removeAt(i);
        _edited = true;
      });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ext = context.ext;
    final text = Theme.of(context).textTheme;
    final r = widget.request;
    final total = _lines.fold<double>(0, (s, l) => s + l.lineTotal);
    final alcohol = _lines.any((l) => l.isAlcohol);

    return Padding(
      padding: EdgeInsets.fromLTRB(
          t.spacing.md, 0, t.spacing.md, t.spacing.md + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('${r.tableName} · ${r.guestName}', style: text.titleLarge)),
              if (r.roundNo != null)
                Text('Round ${r.roundNo}',
                    style: text.bodySmall?.copyWith(color: t.color.content.secondary)),
            ],
          ),
          SizedBox(height: t.spacing.sm),
          Flexible(
            child: Container(
              decoration: BoxDecoration(
                color: t.color.background.raised,
                borderRadius: BorderRadius.circular(t.radius.lg),
                border: Border.all(color: t.color.border.subtle, width: t.borderWidth.hairline),
              ),
              child: _lines.isEmpty
                  ? Padding(
                      padding: EdgeInsets.all(t.spacing.md),
                      child: Text('Every line is removed. Reject the round instead.',
                          style: text.bodyMedium?.copyWith(color: t.color.content.secondary)),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _lines.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: t.color.border.subtle),
                      itemBuilder: (context, i) => _lineRow(context, i),
                    ),
            ),
          ),
          if (alcohol) ...[
            SizedBox(height: t.spacing.sm),
            Container(
              padding: EdgeInsets.all(t.spacing.sm),
              decoration: BoxDecoration(
                color: ext.warningSubtle,
                borderRadius: BorderRadius.circular(t.radius.md),
              ),
              child: Text('Alcohol in this round. Check ID if unsure.',
                  style: text.bodySmall?.copyWith(color: ext.onWarningSubtle)),
            ),
          ],
          SizedBox(height: t.spacing.sm),
          Row(
            children: [
              Expanded(child: Text('Round total', style: text.titleSmall)),
              Text(formatInr(total), key: const ValueKey('round-total'), style: text.titleMedium),
            ],
          ),
          SizedBox(height: t.spacing.md),
          AppButton(
            label: 'Confirm & send',
            variant: AppButtonVariant.primary,
            size: AppControlSize.lg,
            onPressed: _lines.isEmpty
                ? null
                : () => Navigator.of(context)
                    .pop(EditConfirmConfirmed(items: List.unmodifiable(_lines), edited: _edited)),
          ),
          SizedBox(height: t.spacing.sm),
          AppButton(
            label: 'Reject with reason',
            size: AppControlSize.lg,
            onPressed: () => Navigator.of(context).pop(const EditConfirmRejected()),
          ),
        ],
      ),
    );
  }

  Widget _lineRow(BuildContext context, int i) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final l = _lines[i];
    final sub = [
      ...l.modifiers.map((m) => m.name).where((n) => n.isNotEmpty),
      if (l.note != null && l.note!.isNotEmpty) 'Note: ${l.note}',
    ].join(' · ');
    return Padding(
      key: ValueKey('edit-line-${l.productId}'),
      padding: EdgeInsets.symmetric(horizontal: t.spacing.sm + 4, vertical: t.spacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.variantName == null ? l.name : '${l.name} ${l.variantName}',
                    style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                if (sub.isNotEmpty)
                  Text(sub, style: text.bodySmall?.copyWith(color: t.color.content.secondary)),
              ],
            ),
          ),
          AppIconButton(
            icon: Icons.remove,
            tooltip: 'One less ${l.name}',
            onPressed: l.quantity > 1 ? () => _setQty(i, l.quantity - 1) : null,
          ),
          SizedBox(
            width: 28,
            child: Text('${l.quantity}',
                textAlign: TextAlign.center,
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          AppIconButton(
            icon: Icons.add,
            tooltip: 'One more ${l.name}',
            onPressed: l.quantity < _maxQty ? () => _setQty(i, l.quantity + 1) : null,
          ),
          AppIconButton(
            icon: Icons.delete_outline,
            tooltip: 'Remove ${l.name}',
            onPressed: () => _remove(i),
          ),
        ],
      ),
    );
  }
}
