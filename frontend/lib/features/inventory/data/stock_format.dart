/// Stock quantity display and counting input (PLAN 1.1). Output must match the
/// backend `formatQty` exactly, including the U+2212 minus sign.
library;

/// `formatStockQty(8410, 'ML', 750, 'btl')` gives "11 btl + 160 ml".
///
/// * packSize > 1: "<whole packs> <packName> + <rest> <unit>", dropping a zero
///   part ("8 btl + 410 ml", "3 btl", "410 ml", "0 ml").
/// * packSize == 1: "<qty> <unit>", up to 3 decimals, trailing zeros trimmed
///   ("5 pc", "1200 g").
/// * Negative quantities get a leading minus sign on the whole string.
String formatStockQty(num qty, String unit, num packSize, String packName) {
  final unitLower = unit.toLowerCase();
  final milli = (qty.abs() * 1000).round();
  final negative = qty < 0 && milli != 0;

  String body;
  final packMilli = (packSize * 1000).round();
  if (packSize > 1 && packMilli > 0) {
    final packs = milli ~/ packMilli;
    final rest = milli % packMilli;
    if (packs > 0 && rest > 0) {
      body = '$packs $packName + ${_decimal(rest)} $unitLower';
    } else if (packs > 0) {
      body = '$packs $packName';
    } else {
      body = '${_decimal(rest)} $unitLower';
    }
  } else {
    body = '${_decimal(milli)} $unitLower';
  }
  return negative ? '−$body' : body;
}

/// Counting input on phones: whole packs plus an open part in base units.
/// `parseStockInput(8, 410, 750)` gives 6410.
num parseStockInput(int bottles, num openPart, num packSize) => bottles * packSize + openPart;

/// Fixed-point text for a value stored in thousandths, trailing zeros trimmed.
String _decimal(int milli) {
  final whole = milli ~/ 1000;
  final frac = milli % 1000;
  if (frac == 0) return '$whole';
  final digits = frac.toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '');
  return '$whole.$digits';
}
