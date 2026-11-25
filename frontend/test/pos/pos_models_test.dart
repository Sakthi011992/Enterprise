import 'package:flutter_test/flutter_test.dart';
import 'package:pos_billing/features/pos/data/pos_models.dart';

Map<String, dynamic> sampleOrderJson() => {
      'id': 'ord-1',
      'orderNumber': 'A-1043',
      'type': 'DINE_IN',
      'status': 'SENT',
      'table': {'id': 't4', 'name': 'R4', 'areaName': 'Rooftop'},
      'covers': 4,
      'waiter': {'id': 'u1', 'name': 'Arun'},
      'openedAt': '2026-11-25T13:42:00.000Z',
      'heldAt': null,
      'billedAt': null,
      'paidAt': null,
      'note': null,
      'items': [
        {
          'id': 'i1',
          'productId': 'p-lager',
          'comboId': null,
          'name': 'Premium Lager',
          'variantName': '650 ml',
          'seat': 1,
          'quantity': 2,
          'status': 'SENT',
          'modifiers': [],
          'note': null,
          'unitPrice': '300.00',
          'gross': '600.00',
          'discount': '0.00',
          'net': '600.00',
          'tax': '30.00',
          'total': '630.00',
          'happyHourPercent': null,
          'isLiquor': true,
          'ticketKind': 'BOT',
          'station': 'BAR',
          'sentAt': '2026-11-25T13:50:00.000Z',
        },
        {
          'id': 'i2',
          'productId': 'p-mojito',
          'name': 'Classic Mojito',
          'seat': null,
          'quantity': 1,
          'status': 'SENT',
          'modifiers': [],
          'unitPrice': '245.00',
          'gross': '245.00',
          'discount': '105.00',
          'net': '140.00',
          'tax': '7.00',
          'total': '147.00',
          'happyHourPercent': '30.00',
          'isLiquor': true,
          'ticketKind': 'BOT',
          'station': 'BAR',
        },
        {
          'id': 'i3',
          'productId': 'p-malt',
          'name': 'Single Malt 12Y',
          'variantName': '60 ml',
          'seat': 2,
          'quantity': 1,
          'status': 'NEW',
          'modifiers': [
            {'optionId': 'o-rocks', 'name': 'On the rocks', 'priceDelta': 0},
          ],
          'note': 'Extra ice',
          'unitPrice': '540',
          'gross': '540.00',
          'discount': '0.00',
          'net': '540.00',
          'tax': '27.00',
          'total': '567.00',
          'happyHourPercent': null,
          'isLiquor': true,
        },
        {
          'id': 'i4',
          'name': 'Chicken Wings',
          'seat': null,
          'quantity': 1,
          'status': 'VOIDED',
          'modifiers': [],
          'unitPrice': '350.00',
          'gross': '350.00',
          'discount': '0.00',
          'net': '350.00',
          'tax': '17.50',
          'total': '367.50',
          'isLiquor': false,
        },
      ],
      'discounts': [
        {
          'id': 'd1',
          'type': 'PERCENT',
          'value': '10',
          'itemIds': ['i2'],
          'amount': '24.50',
          'reason': 'Service delay',
          'approvedBy': 'Priya',
        },
      ],
      'payments': [
        {
          'id': 'pay1',
          'method': 'UPI',
          'amount': '600.00',
          'tipAmount': '0.00',
          'tendered': null,
          'changeGiven': null,
          'reference': '4471',
          'seat': 1,
          'status': 'COMPLETED',
          'createdAt': '2026-11-25T14:10:00.000Z',
        },
      ],
      'totals': {
        'subtotal': '1190.00',
        'discountTotal': '24.50',
        'netSubtotal': '1165.50',
        'serviceCharge': '58.28',
        'taxTotal': '102.10',
        'taxBreakdown': [
          {'name': 'GST (food)', 'rate': 5, 'amount': '12.10'},
          {'name': 'VAT (liquor)', 'rate': 20, 'amount': '90.00'},
        ],
        'roundOff': '0.62',
        'grandTotal': '1326.00',
        'paid': '600.00',
        'due': '726.00',
        'tipTotal': '0.00',
      },
      'invoiceNumber': null,
    };

void main() {
  group('OrderView.fromJson', () {
    test('parses header, table, waiter and dates', () {
      final order = OrderView.fromJson(sampleOrderJson());
      expect(order.orderNumber, 'A-1043');
      expect(order.type, OrderTypes.dineIn);
      expect(order.table?.name, 'R4');
      expect(order.covers, 4);
      expect(order.waiter?.name, 'Arun');
      expect(order.openedAt?.isUtc, isTrue);
      expect(order.isOpen, isTrue);
    });

    test('keeps money as two-decimal strings and exposes numeric views', () {
      final order = OrderView.fromJson(sampleOrderJson());
      expect(order.totals.grandTotal, '1326.00');
      expect(order.totals.grandTotalValue, 1326);
      expect(order.totals.due, '726.00');
      expect(order.items.first.unitPrice, '300.00');
    });

    test('accepts money sent as JSON numbers', () {
      final order = OrderView.fromJson(sampleOrderJson());
      final malt = order.items.firstWhere((i) => i.id == 'i3');
      expect(malt.unitPrice, '540.00');
      expect(malt.unitPriceValue, 540);
    });

    test('parses modifiers, notes, happy hour and ticket kind', () {
      final order = OrderView.fromJson(sampleOrderJson());
      final malt = order.items.firstWhere((i) => i.id == 'i3');
      expect(malt.modifiers.single.name, 'On the rocks');
      expect(malt.modifierSummary, 'On the rocks');
      expect(malt.note, 'Extra ice');
      expect(malt.isNew, isTrue);
      final mojito = order.items.firstWhere((i) => i.id == 'i2');
      expect(mojito.hasHappyHour, isTrue);
      expect(mojito.happyHourPercent, '30.00');
      final lager = order.items.first;
      expect(lager.isSent, isTrue);
      expect(lager.ticketKind, 'BOT');
    });

    test('liveItems and newItems leave out voided lines', () {
      final order = OrderView.fromJson(sampleOrderJson());
      expect(order.liveItems.map((i) => i.id), ['i1', 'i2', 'i3']);
      expect(order.newItems.map((i) => i.id), ['i3']);
      expect(order.hasUnsent, isTrue);
    });

    test('parses tax breakdown, discounts and payments', () {
      final order = OrderView.fromJson(sampleOrderJson());
      expect(order.totals.taxBreakdown.map((t) => t.name), ['GST (food)', 'VAT (liquor)']);
      expect(order.totals.taxBreakdown.last.rate, 20);
      expect(order.discounts.single.isWholeBill, isFalse);
      expect(order.discounts.single.approvedBy, 'Priya');
      expect(order.payments.single.method, PaymentMethods.upi);
      expect(order.payments.single.reference, '4471');
      expect(order.payments.single.amountValue, 600);
    });

    test('tolerates a takeaway order with no table, waiter or totals', () {
      final order = OrderView.fromJson({
        'id': 'ord-2',
        'orderNumber': 'A-1044',
        'type': 'TAKEAWAY',
        'status': 'OPEN',
        'table': null,
        'waiter': null,
        'totals': <String, dynamic>{},
      });
      expect(order.table, isNull);
      expect(order.waiter, isNull);
      expect(order.totals.grandTotal, '0.00');
      expect(order.items, isEmpty);
      expect(order.isOpen, isTrue);
    });

    test('status helpers', () {
      final paid = OrderView.fromJson({...sampleOrderJson(), 'status': 'PAID'});
      expect(paid.isPaid, isTrue);
      expect(paid.isOpen, isFalse);
      final held = OrderView.fromJson({...sampleOrderJson(), 'heldAt': '2026-11-25T14:00:00.000Z'});
      expect(held.isHeld, isTrue);
    });
  });

  group('requests', () {
    test('CreateOrder.toJson carries offlineId and drops nulls', () {
      const order = CreateOrder(
        type: OrderTypes.dineIn,
        tableId: 't4',
        covers: 4,
        items: [AddItem(productId: 'p-lager', quantity: 2, modifierOptionIds: ['o1'])],
      );
      final json = order.withOfflineId('offline-1').toJson();
      expect(json['type'], 'DINE_IN');
      expect(json['tableId'], 't4');
      expect(json['offlineId'], 'offline-1');
      expect(json.containsKey('waiterId'), isFalse);
      expect(json.containsKey('note'), isFalse);
      expect((json['items'] as List).single, {
        'productId': 'p-lager',
        'quantity': 2,
        'modifierOptionIds': ['o1'],
      });
    });

    test('CreateOrder survives a JSON round trip', () {
      const order = CreateOrder(
        type: OrderTypes.takeaway,
        offlineId: 'abc',
        items: [AddItem(comboId: 'c1')],
      );
      final back = CreateOrder.fromJson(order.toJson());
      expect(back.type, OrderTypes.takeaway);
      expect(back.offlineId, 'abc');
      expect(back.items.single.comboId, 'c1');
      expect(back.items.single.productId, isNull);
    });

    test('AddItem needs exactly one of productId or comboId', () {
      expect(() => AddItem(), throwsA(isA<AssertionError>()));
      expect(() => AddItem(productId: 'p', comboId: 'c'), throwsA(isA<AssertionError>()));
      expect(AddItem(productId: 'p').toJson()['productId'], 'p');
    });

    test('PaymentRequest serialises tips and completeSeat', () {
      const request = PaymentRequest(
        payments: [
          PaymentInput(method: PaymentMethods.cash, amount: '500.00', tendered: '500.00', seat: 2),
        ],
        tipAmount: '50.95',
        completeSeat: 2,
      );
      final json = request.toJson();
      expect(json['tipAmount'], '50.95');
      expect(json['completeSeat'], 2);
      expect((json['payments'] as List).single, {
        'method': 'CASH',
        'amount': '500.00',
        'tendered': '500.00',
        'seat': 2,
      });
    });
  });

  group('menu and tables', () {
    test('PosMenu.fromJson finds groups for a product and active happy hours', () {
      final menu = PosMenu.fromJson({
        'categories': [
          {'id': 'c1', 'name': 'Spirits', 'color': '#B45309', 'sortOrder': 1},
        ],
        'products': [
          {
            'id': 'p-malt',
            'name': 'Single Malt 12Y',
            'categoryId': 'c1',
            'price': '280',
            'is86': false,
            'variants': [
              {'id': 'v30', 'name': '30 ml', 'price': '280.00', 'isDefault': true},
              {'id': 'v60', 'name': '60 ml', 'price': '540.00'},
            ],
            'modifierGroupIds': ['g-serve'],
          },
        ],
        'modifierGroups': [
          {
            'id': 'g-serve',
            'name': 'How to serve',
            'minSelect': 1,
            'maxSelect': 1,
            'options': [
              {'id': 'o-rocks', 'name': 'On the rocks', 'priceDelta': '0'},
              {'id': 'o-soda', 'name': 'With soda', 'priceDelta': '40'},
            ],
          },
        ],
        'priceRules': [
          {
            'id': 'hh',
            'name': 'Happy hour',
            'percentOff': '30',
            'activeNow': true,
            'endsAt': '2026-11-25T14:30:00.000Z',
          },
        ],
        'settings': {'serviceChargePercent': '5', 'serviceChargeTypes': ['DINE_IN']},
      });
      final product = menu.productById('p-malt');
      expect(product?.defaultVariant?.id, 'v30');
      expect(menu.groupsFor(product!).single.options.last.priceDeltaValue, 40);
      expect(menu.activeHappyHours.single.endsAt, isNotNull);
      expect(menu.settings.serviceChargePercentValue, 5);
      expect(menu.categories.single.color, '#B45309');
    });

    test('TableView parses live order and seat fit', () {
      final table = TableView.fromJson({
        'id': 't5',
        'name': 'R5',
        'areaId': 'a1',
        'seats': 2,
        'shape': 'ROUND',
        'posX': 1,
        'posY': 2,
        'status': 'OCCUPIED',
        'mergedIntoId': null,
        'order': {
          'id': 'o5',
          'orderNumber': 'A-1040',
          'covers': 2,
          'grandTotal': '880.00',
          'openedAt': '2026-11-25T13:00:00.000Z',
          'waiterName': 'Arun',
        },
      });
      expect(table.fits(4), isFalse);
      expect(table.fits(2), isTrue);
      expect(table.order?.grandTotal, '880.00');
      expect(table.isFree, isFalse);
    });
  });

  group('approvals and day close', () {
    test('ApprovalView parses status helpers', () {
      final approval = ApprovalView.fromJson({
        'id': 'ap1',
        'type': 'DISCOUNT',
        'status': 'APPROVED',
        'orderId': 'o1',
        'payload': {'type': 'PERCENT', 'value': '20.00', 'itemIds': [], 'reason': 'Staff meal'},
        'reason': 'Staff meal',
      });
      expect(approval.isApproved, isTrue);
      expect(approval.isFinal, isTrue);
      expect(approval.payload['value'], '20.00');
    });

    test('DayCloseTotals parses the PLAN 1.6 shape', () {
      final totals = DayCloseTotals.fromJson({
        'businessDate': '2026-11-25',
        'orders': {'count': 12, 'paid': 10, 'void': 1, 'open': 1},
        'gross': '9800.00',
        'discounts': '240.00',
        'serviceCharge': '400.00',
        'tax': [
          {'name': 'GST (food)', 'rate': 5, 'amount': '220.00'},
        ],
        'roundOff': '-0.40',
        'net': '9960.00',
        'tips': '150.00',
        'byPayment': [
          {'method': 'CASH', 'count': 4, 'amount': '2100.00'},
        ],
        'byType': [
          {'type': 'DINE_IN', 'count': 9, 'amount': '9200.00'},
        ],
        'byCategory': [
          {'categoryId': 'c1', 'name': 'Spirits', 'quantity': 40, 'amount': '6000.00'},
        ],
        'voids': {'count': 1, 'amount': '350.00'},
        'refunds': {'count': 0, 'amount': '0.00'},
        'discountsByStaff': [
          {'userId': 'u1', 'name': 'Arun', 'amount': '120.00'},
        ],
        'cashExpected': '2100.00',
      });
      expect(totals.ordersPaid, 10);
      expect(totals.byPayment.single.key, 'CASH');
      expect(totals.byType.single.key, 'DINE_IN');
      expect(totals.voids.amountValue, 350);
      expect(totals.cashExpectedValue, 2100);
      expect(totals.netValue, 9960);
    });
  });
}
