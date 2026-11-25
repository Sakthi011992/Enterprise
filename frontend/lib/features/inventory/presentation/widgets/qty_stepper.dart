import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';

/// Minus, value, plus. Used for bottles, cases and purchase units. Buttons use
/// the density control height, so they are 52 px touch targets on POS density.
class QtyStepper extends StatelessWidget {
  const QtyStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max,
    this.unitLabel,
    this.enabled = true,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int? max;

  /// Shown after the number, for example "btl" or "cases".
  final String? unitLabel;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final canDown = enabled && value > min;
    final canUp = enabled && (max == null || value < max!);
    final size = context.ext.controlHeight(context.ext.defaultControlSize);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: AppIconButton(
            icon: Icons.remove,
            tooltip: 'One less',
            onPressed: canDown ? () => onChanged(value - 1) : null,
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 56),
          child: Text(
            unitLabel == null ? '$value' : '$value $unitLabel',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        SizedBox(
          width: size,
          height: size,
          child: AppIconButton(
            icon: Icons.add,
            tooltip: 'One more',
            onPressed: canUp ? () => onChanged(value + 1) : null,
          ),
        ),
        SizedBox(width: t.spacing.xs),
      ],
    );
  }
}
