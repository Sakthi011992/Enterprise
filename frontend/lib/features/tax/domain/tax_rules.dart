import '../data/tax_repository.dart';

/// Percent values are compared in hundredths so that 2.5 + 2.5 equals 5 exactly.
int _hundredths(double percent) => (percent * 100).round();

/// True when the components add up to [rate].
bool componentsMatchRate(double rate, List<TaxComponent> components) {
  if (components.isEmpty) return false;
  final sum = components.fold<int>(0, (total, c) => total + _hundredths(c.rate));
  return sum == _hundredths(rate);
}

/// Form message for a tax class, or null when the components match the rate.
String? taxComponentsError(double rate, List<TaxComponent> components) {
  if (components.isEmpty) return 'Add at least one component, such as CGST.';
  if (componentsMatchRate(rate, components)) return null;
  final sum = components.fold<double>(0, (total, c) => total + c.rate);
  return 'Components add up to ${sum.toStringAsFixed(2)}%, but the rate is ${rate.toStringAsFixed(2)}%.';
}

/// Preview of an invoice number such as INV/2026-27/000001. The financial year
/// starts in April, as in the invoice numbering spec.
String invoicePreview(String prefix, DateTime date) {
  final startYear = date.month >= 4 ? date.year : date.year - 1;
  final endShort = ((startYear + 1) % 100).toString().padLeft(2, '0');
  final clean = prefix.trim().isEmpty ? 'INV' : prefix.trim();
  return '$clean/$startYear-$endShort/000001';
}
