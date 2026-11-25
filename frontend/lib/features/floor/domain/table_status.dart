import '../../../core/ui/ui.dart';
import '../data/floor_repository.dart';

/// Label and tone for a table status. The tone sets the colour; the label is
/// always shown too, so colour is never the only signal.
class TableStatusStyle {
  const TableStatusStyle(this.label, this.tone);

  final String label;
  final StatusTone tone;
}

TableStatusStyle tableStatusStyle(String status) => switch (status) {
      TableStatus.free => const TableStatusStyle('Free', StatusTone.success),
      TableStatus.occupied => const TableStatusStyle('Occupied', StatusTone.info),
      TableStatus.billPrinted => const TableStatusStyle('Bill printed', StatusTone.warning),
      TableStatus.cleaning => const TableStatusStyle('Cleaning', StatusTone.neutral),
      TableStatus.reserved => const TableStatusStyle('Reserved', StatusTone.info),
      _ => const TableStatusStyle('Unknown', StatusTone.neutral),
    };

/// Statuses a manager can set by hand. OCCUPIED and BILL_PRINTED come from orders.
const manualTableStatuses = [TableStatus.free, TableStatus.cleaning, TableStatus.reserved];
