import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../data/inventory_models.dart';

/// Badge for `StockItemRow.status` (OK, BELOW_PAR, VARIANCE, EXPIRES, NEGATIVE).
class StockStatusBadge extends StatelessWidget {
  const StockStatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (status) {
      StockStatus.belowPar => ('Below par', StatusTone.warning),
      StockStatus.variance => ('Variance', StatusTone.warning),
      StockStatus.expires => ('Expires soon', StatusTone.warning),
      StockStatus.negative => ('Negative', StatusTone.danger),
      _ => ('OK', StatusTone.success),
    };
    return StatusBadge(label: label, tone: tone);
  }
}
