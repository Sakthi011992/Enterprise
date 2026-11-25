/// Count rules shared by the stock count screen and its tests (PLAN 1.7:
/// a count is an outlier when its difference from expected is more than 30%).
library;

const double countOutlierPercent = 30;

/// Difference from expected, in percent of expected (negative when the count
/// is lower). Null when expected is zero, because a percentage is not defined.
double? countDifferencePercent(num expected, num counted) {
  if (expected == 0) return null;
  return (counted - expected) / expected.abs() * 100;
}

/// True when the count differs from expected by more than [countOutlierPercent].
/// Compares by multiplying out, so exactly 30% is not an outlier and the result
/// does not depend on floating-point division.
bool isCountOutlier(num expected, num counted) {
  if (expected == 0) return false;
  return (counted - expected).abs() * 100 > countOutlierPercent * expected.abs();
}

/// Warning text for an outlier, as on the MobileStock board:
/// "Expected about 3 bottles. This count is 60% lower. Recount, or add a note."
String countOutlierMessage({required String expectedDisplay, required double percent}) {
  final direction = percent < 0 ? 'lower' : 'higher';
  return 'Expected about $expectedDisplay. This count is ${percent.abs().round()}% '
      '$direction. Recount, or add a note.';
}
