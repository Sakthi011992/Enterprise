import 'package:flutter_test/flutter_test.dart';
import 'package:pos_billing/features/hardware/domain/printer_rules.dart';
import 'package:pos_billing/features/reports/domain/cash_variance.dart';

void main() {
  group('printer address rules', () {
    test('accepts dotted IPv4 addresses', () {
      expect(isValidIPv4('192.168.1.30'), isTrue);
      expect(isValidIPv4(' 10.0.0.1 '), isTrue);
    });

    test('rejects out-of-range octets and non-addresses', () {
      expect(isValidIPv4('256.1.1.1'), isFalse);
      expect(isValidIPv4('192.168.1'), isFalse);
      expect(isValidIPv4('printer'), isFalse);
      expect(isValidIPv4(''), isFalse);
    });

    test('LAN printers need a valid IP and port', () {
      expect(lanAddressError(host: '192.168.1.30', port: '9100'), isNull);
      expect(lanAddressError(host: '192.168.1', port: '9100'), isNotNull);
      expect(lanAddressError(host: '192.168.1.30', port: '70000'), isNotNull);
      expect(lanAddressError(host: '192.168.1.30', port: 'abc'), isNotNull);
    });
  });

  group('cash variance for the Z report', () {
    test('counted equal to expected matches', () {
      final paise = cashVarianceInPaise(expected: '4250.00', counted: '4250.00');
      expect(paise, 0);
      expect(varianceLabel(paise), 'Matches expected cash');
    });

    test('more counted than expected is over', () {
      final paise = cashVarianceInPaise(expected: '4250.00', counted: '4260.50');
      expect(paise, 1050);
      expect(varianceLabel(paise), '₹10.50 over');
    });

    test('less counted than expected is short, and the sum stays exact', () {
      final paise = cashVarianceInPaise(expected: '0.30', counted: '0.10');
      expect(paise, -20);
      expect(varianceLabel(paise), '₹0.20 short');
    });
  });
}
