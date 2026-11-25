import 'package:flutter_test/flutter_test.dart';
import 'package:pos_billing/features/inventory/domain/count_rules.dart';

void main() {
  group('count outlier rule (over 30% from expected)', () {
    test('60% lower than expected is an outlier', () {
      // "Expected about 3 bottles. This count is 60% lower."
      expect(countDifferencePercent(3, 1.2), closeTo(-60, 1e-9));
      expect(isCountOutlier(3, 1.2), isTrue);
    });

    test('a 25% difference is not an outlier, a 35% one is', () {
      expect(isCountOutlier(100, 75), isFalse);
      expect(isCountOutlier(100, 65), isTrue);
      expect(isCountOutlier(100, 130), isFalse);
      expect(isCountOutlier(100, 140), isTrue);
    });

    test('exactly 30% is not an outlier', () {
      expect(isCountOutlier(100, 70), isFalse);
    });

    test('no percentage when expected is zero, so no outlier', () {
      expect(countDifferencePercent(0, 5), isNull);
      expect(isCountOutlier(0, 5), isFalse);
    });

    test('warning text matches the board', () {
      expect(
        countOutlierMessage(expectedDisplay: '3 btl', percent: -60),
        'Expected about 3 btl. This count is 60% lower. Recount, or add a note.',
      );
      expect(
        countOutlierMessage(expectedDisplay: '2 btl', percent: 45.4),
        'Expected about 2 btl. This count is 45% higher. Recount, or add a note.',
      );
    });
  });
}
