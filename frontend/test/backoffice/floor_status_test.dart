import 'package:flutter_test/flutter_test.dart';
import 'package:pos_billing/core/ui/ui.dart';
import 'package:pos_billing/features/floor/data/floor_repository.dart';
import 'package:pos_billing/features/floor/domain/table_status.dart';

void main() {
  test('every table status has its label and tone', () {
    expect(tableStatusStyle(TableStatus.free).label, 'Free');
    expect(tableStatusStyle(TableStatus.free).tone, StatusTone.success);
    expect(tableStatusStyle(TableStatus.occupied).label, 'Occupied');
    expect(tableStatusStyle(TableStatus.occupied).tone, StatusTone.info);
    expect(tableStatusStyle(TableStatus.billPrinted).label, 'Bill printed');
    expect(tableStatusStyle(TableStatus.billPrinted).tone, StatusTone.warning);
    expect(tableStatusStyle(TableStatus.cleaning).label, 'Cleaning');
    expect(tableStatusStyle(TableStatus.cleaning).tone, StatusTone.neutral);
    expect(tableStatusStyle(TableStatus.reserved).label, 'Reserved');
    expect(tableStatusStyle(TableStatus.reserved).tone, StatusTone.info);
  });

  test('an unknown status is shown as Unknown, not guessed', () {
    expect(tableStatusStyle('SOMETHING_NEW').label, 'Unknown');
    expect(tableStatusStyle('SOMETHING_NEW').tone, StatusTone.neutral);
  });

  test('free, occupied and bill printed never share a tone', () {
    final tones = {
      tableStatusStyle(TableStatus.free).tone,
      tableStatusStyle(TableStatus.occupied).tone,
      tableStatusStyle(TableStatus.billPrinted).tone,
    };
    // Occupied and reserved share the info tone by design; the label tells them apart.
    expect(tones.length, 3);
  });

  test('staff can only set free, cleaning or reserved by hand', () {
    expect(manualTableStatuses, [TableStatus.free, TableStatus.cleaning, TableStatus.reserved]);
  });

  test('FloorTable.fromJson reads an occupied table with its open order', () {
    final table = FloorTable.fromJson({
      'id': 't4',
      'name': 'R4',
      'areaId': 'indoor',
      'seats': 4,
      'shape': 'SQUARE',
      'posX': 2,
      'posY': 1,
      'status': 'OCCUPIED',
      'mergedIntoId': null,
      'order': {
        'id': 'o1',
        'orderNumber': 'MAIN-7',
        'covers': 2,
        'grandTotal': '540.00',
        'openedAt': '2026-11-25T12:00:00Z',
        'waiterName': 'Priya',
      },
    });
    expect(table.status, TableStatus.occupied);
    expect(table.order?.covers, 2);
    expect(table.order?.grandTotal, '540.00');
    expect(table.isMerged, isFalse);
  });

  test('FloorTable.fromJson treats a merged table as merged and an empty table as having no order', () {
    final table = FloorTable.fromJson({
      'id': 't5',
      'name': 'R5',
      'areaId': 'indoor',
      'seats': 2,
      'shape': 'ROUND',
      'posX': 0,
      'posY': 0,
      'status': 'FREE',
      'mergedIntoId': 't4',
      'order': null,
    });
    expect(table.isMerged, isTrue);
    expect(table.order, isNull);
  });
}
