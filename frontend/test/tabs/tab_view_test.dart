import 'package:flutter_test/flutter_test.dart';
import 'package:pos_billing/core/auth/api_error.dart';
import 'package:pos_billing/features/tabs/data/tabs_models.dart';
import 'package:pos_billing/features/tabs/domain/tab_rules.dart';

Map<String, dynamic> sampleTab({
  String spent = '4700.00',
  String limit = '5000.00',
  int warn = 90,
  Object? percentUsed = 94,
  Object? nearLimit = true,
}) =>
    {
      'id': 'tab-7',
      'number': 'T-07',
      'guestName': 'Karthik R',
      'mobile': null,
      'ageChecked': true,
      'security': 'CARD_PREAUTH',
      'cardLast4': '4821',
      'amountHeld': '5000.00',
      'houseAccount': null,
      'tabLimit': limit,
      'warnAtPercent': warn,
      'spent': spent,
      'remaining': null,
      'percentUsed': percentUsed,
      'nearLimit': nearLimit,
      'linkType': 'BAR_SEAT',
      'linkLabel': 'Bar seat 3',
      'table': null,
      'status': 'OPEN',
      'openedAt': '2026-11-25T13:35:00.000Z',
      'closedAt': null,
      'openedBy': {'id': 'u-meera', 'name': 'Meera'},
      'orderId': 'ord-7',
      'orderStatus': 'OPEN',
      'itemCount': 6,
    };

void main() {
  group('TabView.fromJson', () {
    test('reads near limit from the server flags', () {
      final tab = TabView.fromJson(sampleTab());
      expect(tab.nearLimit, isTrue);
      expect(tab.spentValue, 4700);
      expect(tab.tabLimitValue, 5000);
      expect(tab.percentUsed, 94);
      expect(tab.isOpen, isTrue);
      expect(tab.openedBy?.name, 'Meera');
      expect(tab.securityLabel, 'Card ••4821');
    });

    test('works out near limit from spend when the flag is absent', () {
      // 4700 of 5000 is 94%, which is past a 90% warning point.
      final json = sampleTab(percentUsed: null, nearLimit: null);
      final tab = TabView.fromJson(json);
      expect(tab.percentUsed, closeTo(94, 0.001));
      expect(tab.nearLimit, isTrue);
    });

    test('not near limit below the warning point', () {
      final json = sampleTab(spent: '1100.00', warn: 80, percentUsed: null, nearLimit: null);
      final tab = TabView.fromJson(json);
      expect(tab.nearLimit, isFalse);
    });

    test('accepts percentUsed sent as a string', () {
      final tab = TabView.fromJson(sampleTab(percentUsed: '94.0'));
      expect(tab.percentUsed, 94);
    });

    test('closed tab reports closed', () {
      final json = sampleTab()..['status'] = 'CLOSED';
      final tab = TabView.fromJson(json);
      expect(tab.isClosed, isTrue);
      expect(tab.isOpen, isFalse);
    });
  });

  group('validateOpenTab', () {
    test('an empty card-pre-auth form asks for everything it needs', () {
      final errors = validateOpenTab(const OpenTabDraft());
      expect(errors.containsKey(TabField.guestName), isTrue);
      expect(errors.containsKey(TabField.ageChecked), isTrue);
      expect(errors.containsKey(TabField.cardLast4), isTrue);
      expect(errors.containsKey(TabField.amountHeld), isTrue);
      expect(errors.containsKey(TabField.tabLimit), isTrue);
    });

    test('age must be checked before a tab opens', () {
      const draft = OpenTabDraft(
        guestName: 'Karthik R',
        cardLast4: '4821',
        amountHeld: '5000',
        tabLimit: '5000',
      );
      final errors = validateOpenTab(draft);
      expect(errors.keys, [TabField.ageChecked]);
      final ok = validateOpenTab(
        const OpenTabDraft(
          guestName: 'Karthik R',
          ageChecked: true,
          cardLast4: '4821',
          amountHeld: '5000',
          tabLimit: '5000',
        ),
      );
      expect(ok, isEmpty);
    });

    test('card last 4 must be four digits', () {
      const draft = OpenTabDraft(
        guestName: 'Karthik R',
        ageChecked: true,
        cardLast4: '48',
        amountHeld: '5000',
        tabLimit: '5000',
      );
      expect(validateOpenTab(draft).containsKey(TabField.cardLast4), isTrue);
    });

    test('a deposit needs an amount, a house account needs a name', () {
      const deposit = OpenTabDraft(
        guestName: 'Sana',
        ageChecked: true,
        security: TabSecurities.cashDeposit,
        tabLimit: '8000',
      );
      expect(validateOpenTab(deposit).containsKey(TabField.amountHeld), isTrue);

      const house = OpenTabDraft(
        guestName: 'Corporate guest',
        ageChecked: true,
        security: TabSecurities.houseAccount,
        tabLimit: '50000',
      );
      expect(validateOpenTab(house).containsKey(TabField.houseAccount), isTrue);
    });

    test('a limit above the persona limit shows the design copy', () {
      const draft = OpenTabDraft(
        guestName: 'Karthik R',
        ageChecked: true,
        cardLast4: '4821',
        amountHeld: '5000',
        tabLimit: '10000',
      );
      final errors = validateOpenTab(draft, personaLimit: 5000);
      expect(errors[TabField.tabLimit], '₹10,000 is above your ₹5,000 limit');
      expect(validateOpenTab(draft), isEmpty, reason: 'no persona limit, no check');
    });

    test('security NONE needs no security fields (approval is asked for in the UI)', () {
      const draft = OpenTabDraft(
        guestName: 'Walk-in 4',
        ageChecked: true,
        security: TabSecurities.none,
        tabLimit: '3000',
      );
      expect(validateOpenTab(draft), isEmpty);
    });
  });

  group('tab error copy', () {
    test('TAB_LIMIT_REACHED names the tab and the limit', () {
      const err = ApiError(
        status: 409,
        code: 'TAB_LIMIT_REACHED',
        message: 'raw',
        details: {'tabId': 'tab-7', 'number': 'T-07', 'limit': 5000, 'spent': 4700, 'attempted': 5200},
      );
      expect(
        tabErrorMessage(err),
        'Tab T-07 has reached its ₹5,000 limit. Ask a manager to raise it or close the tab.',
      );
    });

    test('unknown codes show the server message', () {
      const err = ApiError(status: 400, code: 'SOMETHING_NEW', message: 'Server says no');
      expect(tabErrorMessage(err), 'Server says no');
    });

    test('date helpers write the API and display forms', () {
      expect(isoDate(DateTime(2026, 2, 3)), '2026-02-03');
      expect(shortDate(DateTime(2026, 11, 12)), '12 Nov');
    });
  });
}
