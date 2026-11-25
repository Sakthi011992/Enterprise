/// Client-side GRN math for the live preview on the receiving screen (PLAN 1.7
/// GRN post rules). The server's numbers are the ones saved; this keeps the
/// preview text in step while the storekeeper types.
library;

import '../../pos/presentation/pos_format.dart';
import '../data/procurement_models.dart';

/// Status of one line, as the server names it.
String grnLineStatus(GrnLine line) {
  if (line.invoicedQty > line.orderedQty) return 'OVER_INVOICED';
  if (line.damagedQty > 0) return 'DAMAGED';
  if (line.receivedQty < line.invoicedQty) return 'SHORT';
  return 'OK';
}

/// Lowercase first word of a purchase unit name: "Case of 12 bottles" gives
/// "case", "Keg" gives "keg".
String unitWord(String purchaseUnitName) {
  final trimmed = purchaseUnitName.trim();
  if (trimmed.isEmpty) return 'unit';
  return trimmed.split(RegExp(r'\s+')).first.toLowerCase();
}

/// Totals the receiving screen shows next to the lines.
class GrnTotals {
  const GrnTotals({
    required this.stockByUnit,
    required this.damagedByUnit,
    required this.shortByUnit,
    required this.receivedValue,
    required this.damagedValue,
    required this.debitNote,
    required this.invoiceValue,
    required this.payable,
    required this.mismatch,
  });

  /// Good stock added per unit word (received minus damaged), in line order.
  final Map<String, num> stockByUnit;

  /// Unit words of lines with damage, in line order.
  final List<String> damagedByUnit;

  /// Unit words of lines invoiced but not received, in line order.
  final List<String> shortByUnit;

  final double receivedValue;
  final double damagedValue;
  final double debitNote;
  final double invoiceValue;
  final double payable;

  /// Any invoiced quantity differs from ordered, or the invoice total differs
  /// from the sum of invoiced lines by more than ₹1.
  final bool mismatch;
}

/// Sums the lines the way the server does. [invoiceValue] defaults to the sum
/// of invoiced quantity times rate.
GrnTotals grnTotals(List<GrnLine> lines, {double? invoiceValue}) {
  final stock = <String, num>{};
  final damagedUnits = <String>[];
  final shortUnits = <String>[];
  var received = 0.0;
  var damaged = 0.0;
  var debit = 0.0;
  var invoicedSum = 0.0;
  var quantityMismatch = false;

  for (final l in lines) {
    final word = unitWord(l.purchaseUnitName);
    final good = l.receivedQty - l.damagedQty;
    if (good > 0) stock[word] = (stock[word] ?? 0) + good;
    if (l.damagedQty > 0) damagedUnits.add(word);
    final short = l.invoicedQty - l.receivedQty;
    if (short > 0) {
      shortUnits.add(word);
      debit += short * l.rate;
    }
    received += l.receivedQty * l.rate;
    damaged += l.damagedQty * l.rate;
    invoicedSum += l.invoicedQty * l.rate;
    if (l.invoicedQty != l.orderedQty) quantityMismatch = true;
  }

  final invoice = invoiceValue ?? invoicedSum;
  final totalDiffers = (invoice - invoicedSum).abs() > 1;
  return GrnTotals(
    stockByUnit: stock,
    damagedByUnit: damagedUnits,
    shortByUnit: shortUnits,
    receivedValue: roundPaise(received),
    damagedValue: roundPaise(damaged),
    debitNote: roundPaise(debit),
    invoiceValue: roundPaise(invoice),
    payable: roundPaise(invoice - debit),
    mismatch: quantityMismatch || totalDiffers,
  );
}

/// Sentence under the lines, from the design:
/// "Posting creates: stock +13 cases +4 kegs in Cellar, a debit note of
/// ₹7,800 for the missing keg, and ₹950 wastage for the damaged case."
String grnPreviewSentence(GrnTotals totals, {required String locationName}) {
  final parts = <String>[];

  if (totals.stockByUnit.isNotEmpty) {
    final stockText = [
      for (final e in totals.stockByUnit.entries)
        '+${_qty(e.value)} ${_plural(e.key, e.value)}',
    ].join(' ');
    parts.add('stock $stockText in $locationName');
  }
  if (totals.debitNote > 0) {
    final word = _single(totals.shortByUnit);
    parts.add('a debit note of ${formatRupees(totals.debitNote)} for the missing $word');
  }
  if (totals.damagedValue > 0) {
    final word = _single(totals.damagedByUnit);
    parts.add('${formatRupees(totals.damagedValue)} wastage for the damaged $word');
  }
  if (parts.isEmpty) return 'Posting creates nothing to stock or credit yet.';
  return 'Posting creates: ${_joinList(parts)}.';
}

/// Singular unit word when every entry agrees, otherwise "items".
String _single(List<String> words) {
  if (words.isEmpty) return 'items';
  final first = words.first;
  return words.every((w) => w == first) ? first : 'items';
}

String _plural(String word, num qty) => qty == 1 ? word : '${word}s';

String _qty(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
}

String _joinList(List<String> items) {
  if (items.length == 1) return items.first;
  if (items.length == 2) return '${items[0]} and ${items[1]}';
  return '${items.sublist(0, items.length - 1).join(', ')}, and ${items.last}';
}
