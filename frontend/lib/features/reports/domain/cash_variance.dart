/// Cash difference for the Z report, in paise so that no float error creeps in.
/// Positive means more cash counted than expected (over), negative means short.
int cashVarianceInPaise({required String expected, required String counted}) {
  return _paise(counted) - _paise(expected);
}

int _paise(String amount) {
  final value = double.tryParse(amount.trim()) ?? 0;
  return (value * 100).round();
}

/// Text for the variance line on the Z report.
String varianceLabel(int paise) {
  if (paise == 0) return 'Matches expected cash';
  final rupees = (paise.abs() / 100).toStringAsFixed(2);
  return paise > 0 ? '₹$rupees over' : '₹$rupees short';
}
