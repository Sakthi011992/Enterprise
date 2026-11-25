import 'package:flutter_test/flutter_test.dart';
import 'package:pos_billing/core/auth/api_error.dart';
import 'package:pos_billing/features/kds/data/kds_models.dart';
import 'package:pos_billing/features/kds/domain/kds_rules.dart';

Map<String, dynamic> sampleTicketJson({String status = 'NEW', String? readyAt}) => {
      'id': 'tk-2291',
      'kind': 'BOT',
      'station': 'BAR',
      'seq': 2291,
      'label': 'BOT 2291',
      'kdsStatus': status,
      'order': {
        'id': 'o-1043',
        'orderNumber': 'A-1043',
        'type': 'DINE_IN',
        'tableName': 'R4',
        'tabNumber': null,
        'waiterName': 'Arun',
        'covers': 4,
      },
      'items': [
        {
          'orderItemId': 'i-1',
          'name': 'Single Malt 12Y',
          'variantName': '60 ml',
          'quantity': 1,
          'modifiers': ['On the rocks'],
          'note': null,
          'seat': 2,
          'voided': false,
        },
        {
          'orderItemId': 'i-2',
          'name': 'Old Fashioned',
          'variantName': null,
          'quantity': 1,
          'modifiers': <String>[],
          'note': null,
          'seat': null,
          'voided': true,
        },
      ],
      'createdAt': '2026-11-25T14:00:00.000Z',
      'startedAt': null,
      'readyAt': readyAt,
      'servedAt': null,
      'ageSeconds': 42,
      'colour': 'green',
    };

void main() {
  group('KdsTicket.fromJson', () {
    test('reads the contract keys and the status helpers', () {
      final ticket = KdsTicket.fromJson(sampleTicketJson());

      expect(ticket.label, 'BOT 2291');
      expect(ticket.isNew, isTrue);
      expect(ticket.order.placeLabel, 'R4');
      expect(ticket.order.waiterName, 'Arun');
      expect(ticket.items.first.modifiers, ['On the rocks']);
      expect(ticket.items.first.headline, '1 × Single Malt 12Y 60 ml');
      expect(ticket.liveItems.length, 1, reason: 'voided lines are not live');
      expect(ticket.createdAt, DateTime.parse('2026-11-25T14:00:00.000Z'));
    });

    test('places a takeaway or tab ticket by tab number when no table', () {
      final json = sampleTicketJson();
      json['order'] = {
        'id': 'o-2',
        'orderNumber': 'A-1044',
        'type': 'BAR_COUNTER',
        'tableName': null,
        'tabNumber': 'T-08',
        'covers': 1,
      };
      final ticket = KdsTicket.fromJson(json);
      expect(ticket.order.placeLabel, 'Tab T-08');
    });

    test('a READY ticket is in the ready column', () {
      final ticket = KdsTicket.fromJson(sampleTicketJson(status: 'READY'));
      expect(ticket.isReady, isTrue);
      expect(columnFor(ticket), KdsColumn.ready);
      expect(actionsFor(ticket), [KdsAction.recall, KdsAction.served]);
    });
  });

  group('colour thresholds (green under 5 min, amber 5-10, red over 10)', () {
    test('colourForAge at the edges', () {
      expect(colourForAge(const Duration(minutes: 4, seconds: 59)), TicketColour.green);
      expect(colourForAge(const Duration(minutes: 5)), TicketColour.amber);
      expect(colourForAge(const Duration(minutes: 10)), TicketColour.amber);
      expect(colourForAge(const Duration(minutes: 10, seconds: 1)), TicketColour.red);
    });

    test('colour stops at readyAt once the ticket is READY', () {
      final created = DateTime.parse('2026-11-25T14:00:00Z');
      final now = created.add(const Duration(minutes: 20));
      expect(
        ticketColourAt(createdAt: created, readyAt: created.add(const Duration(minutes: 3)), now: now),
        TicketColour.green,
      );
      expect(ticketColourAt(createdAt: created, now: now), TicketColour.red);
    });

    test('unknown server colour falls back to green', () {
      expect(colourFromWire('amber'), TicketColour.amber);
      expect(colourFromWire('red'), TicketColour.red);
      expect(colourFromWire('purple'), TicketColour.green);
    });
  });

  group('age and average text', () {
    test('formatTicketAge is m:ss with seconds padded', () {
      expect(formatTicketAge(const Duration(seconds: 42)), '0:42');
      expect(formatTicketAge(const Duration(seconds: 70)), '1:10');
      expect(formatTicketAge(const Duration(seconds: 680)), '11:20');
      expect(formatTicketAge(const Duration(seconds: -5)), '0:00');
    });

    test('avgTicketLabel matches the board copy', () {
      expect(avgTicketLabel(292), 'Avg ticket time today 4:52');
    });

    test('readyForLabel counts whole minutes', () {
      expect(readyForLabel(const Duration(seconds: 30)), 'Ready just now');
      expect(readyForLabel(const Duration(minutes: 1, seconds: 5)), 'Ready 1 min');
    });
  });

  group('board helpers', () {
    test('lastBumped picks the READY ticket with the latest readyAt', () {
      final early = KdsTicket.fromJson(sampleTicketJson(status: 'READY', readyAt: '2026-11-25T14:01:00Z'));
      final late = KdsTicket.fromJson(sampleTicketJson(status: 'READY', readyAt: '2026-11-25T14:05:00Z'));
      final fresh = KdsTicket.fromJson(sampleTicketJson());
      expect(lastBumped([early, late, fresh]), same(late));
      expect(lastBumped([fresh]), isNull);
    });

    test('KdsBoard clockOffset is server time minus receipt time', () {
      final received = DateTime.parse('2026-11-25T14:00:00Z');
      final board = KdsBoard.fromJson(
        {
          'serverTime': '2026-11-25T14:00:30.000Z',
          'tickets': [sampleTicketJson()],
          'allDay': [
            {'name': 'Premium Lager', 'variantName': null, 'quantity': 148},
          ],
          'avgTicketSeconds': 292,
        },
        receivedAt: received,
      );
      expect(board.clockOffset, const Duration(seconds: 30));
      expect(board.withStatus('NEW').length, 1);
      expect(board.allDay.first.quantity, 148);
      expect(board.avgTicketSeconds, 292);
    });

    test('kdsErrorMessage explains a bad state in plain words', () {
      const bad = ApiError(status: 409, code: 'KDS_BAD_STATE', message: 'raw');
      expect(kdsErrorMessage(bad), contains('already moved on'));
      const late = ApiError(status: 409, code: 'RECALL_TOO_LATE', message: 'raw');
      expect(kdsErrorMessage(late), contains('30 minutes'));
    });
  });
}
