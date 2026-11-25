import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../data/pos_models.dart';
import '../modifier_rules.dart';
import '../pos_format.dart';
import 'dialog_frame.dart';

/// What the sheet returns when staff add the product.
class ModifierSelection {
  const ModifierSelection({
    this.variantId,
    this.optionIds = const [],
    required this.seat,
    this.note,
    this.quantity = 1,
  });

  final String? variantId;
  final List<String> optionIds;
  final int seat;
  final String? note;
  final int quantity;
}

/// Bottom sheet for a product with modifier groups, or a variant choice. Enforces
/// each group's min and max. Resolves to null when dismissed.
Future<ModifierSelection?> showModifierSheet(
  BuildContext context, {
  required PosProduct product,
  PosVariant? variant,
  required List<PosModifierGroup> groups,
  required int covers,
  int initialSeat = 1,
}) {
  return showModalBottomSheet<ModifierSelection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ModifierSheet(
      product: product,
      variant: variant,
      groups: groups,
      covers: covers < 1 ? 1 : covers,
      initialSeat: initialSeat,
    ),
  );
}

class _ModifierSheet extends StatefulWidget {
  const _ModifierSheet({
    required this.product,
    this.variant,
    required this.groups,
    required this.covers,
    required this.initialSeat,
  });

  final PosProduct product;
  final PosVariant? variant;
  final List<PosModifierGroup> groups;
  final int covers;
  final int initialSeat;

  @override
  State<_ModifierSheet> createState() => _ModifierSheetState();
}

class _ModifierSheetState extends State<_ModifierSheet> {
  late String? _variantId = widget.variant?.id ?? widget.product.defaultVariant?.id;
  final Set<String> _selected = {};
  late int _seat = widget.initialSeat.clamp(1, widget.covers).toInt();
  int _quantity = 1;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  PosVariant? get _variant {
    for (final v in widget.product.variants) {
      if (v.id == _variantId) return v;
    }
    return null;
  }

  num get _unitPrice {
    final base = _variant?.priceValue ?? widget.product.priceValue;
    return base + modifierDelta(widget.groups, _selected);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context);
    final errors = modifierErrors(widget.groups, _selected);
    final valid = errors.isEmpty;

    return Padding(
      padding: EdgeInsets.only(
        left: t.spacing.lg,
        right: t.spacing.lg,
        top: t.spacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + t.spacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.product.name, style: theme.textTheme.titleLarge),
            SizedBox(height: t.spacing.xs),
            Text(
              'Modifiers and notes',
              style: TextStyle(color: t.color.content.secondary),
            ),
            if (widget.product.variants.length > 1) ...[
              SizedBox(height: t.spacing.md),
              _SectionLabel('Size'),
              Wrap(
                spacing: t.spacing.sm,
                runSpacing: t.spacing.sm,
                children: [
                  for (final v in widget.product.variants)
                    PosChoiceChip(
                      label: '${v.name} ${formatWire(v.price)}',
                      selected: v.id == _variantId,
                      onTap: () => setState(() => _variantId = v.id),
                    ),
                ],
              ),
            ],
            for (final group in widget.groups) ...[
              SizedBox(height: t.spacing.md),
              _SectionLabel(_groupHeading(group)),
              Wrap(
                spacing: t.spacing.sm,
                runSpacing: t.spacing.sm,
                children: [
                  for (final option in group.options)
                    PosChoiceChip(
                      label: option.priceDeltaValue == 0
                          ? option.name
                          : '${option.name} +${formatRupees(option.priceDeltaValue)}',
                      selected: _selected.contains(option.id),
                      onTap: () => setState(() {
                        final next = toggleModifierOption(group, _selected, option.id);
                        _selected
                          ..clear()
                          ..addAll(next);
                      }),
                    ),
                ],
              ),
              if (errors[group.id] != null) ...[
                SizedBox(height: t.spacing.xs),
                Text(
                  errors[group.id]!,
                  style: TextStyle(color: t.color.content.danger, fontWeight: FontWeight.w600),
                ),
              ],
            ],
            SizedBox(height: t.spacing.md),
            const _SectionLabel('Seat'),
            Wrap(
              spacing: t.spacing.sm,
              runSpacing: t.spacing.sm,
              children: [
                for (var s = 1; s <= widget.covers; s++)
                  PosChoiceChip(
                    label: 'Seat $s',
                    selected: _seat == s,
                    onTap: () => setState(() => _seat = s),
                  ),
              ],
            ),
            SizedBox(height: t.spacing.md),
            AppTextField(label: 'Note for the kitchen or bar', controller: _note),
            SizedBox(height: t.spacing.md),
            Row(
              children: [
                _StepperButton(
                  icon: Icons.remove,
                  tooltip: 'Less',
                  onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    '$_quantity',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                _StepperButton(
                  icon: Icons.add,
                  tooltip: 'More',
                  onPressed: () => setState(() => _quantity++),
                ),
                const Spacer(),
                Text(
                  formatRupees(_unitPrice * _quantity),
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            SizedBox(height: t.spacing.xs),
            Text(
              'The final price is confirmed on the order, after happy hour and area pricing.',
              style: TextStyle(color: t.color.content.muted, fontSize: 12),
            ),
            SizedBox(height: t.spacing.lg),
            AppButton(
              label: valid ? 'Add to order' : 'Fix the options above',
              variant: AppButtonVariant.primary,
              onPressed: valid
                  ? () => Navigator.of(context).pop(
                        ModifierSelection(
                          variantId: _variantId,
                          optionIds: _selected.toList(),
                          seat: _seat,
                          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
                          quantity: _quantity,
                        ),
                      )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  static String _groupHeading(PosModifierGroup g) {
    if (g.minSelect > 0) return '${g.name} (required)';
    return g.name;
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.only(bottom: t.spacing.xs),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: t.color.content.secondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.tooltip, this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ext = context.ext;
    return SizedBox.square(
      dimension: ext.controlHeight(AppControlSize.md),
      child: IconButton.outlined(
        tooltip: tooltip,
        icon: Icon(icon),
        onPressed: onPressed,
      ),
    );
  }
}
