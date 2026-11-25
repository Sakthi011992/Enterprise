import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';

final dayCloseRepositoryProvider = Provider<DayCloseRepository>(
  (ref) => DayCloseRepository(ref.watch(dioProvider)),
);

String _money(Object? v) => v?.toString() ?? '0.00';

class NamedAmount {
  const NamedAmount({required this.label, required this.count, required this.amount});

  final String label;
  final int count;
  final String amount;
}

/// Totals for the business date (PLAN 1.6). Money is kept as the server's strings.
class DaySummary {
  const DaySummary({
    required this.businessDate,
    required this.paid,
    required this.voidCount,
    required this.openCount,
    required this.gross,
    required this.discounts,
    required this.serviceCharge,
    required this.roundOff,
    required this.net,
    required this.tips,
    required this.cashExpected,
    required this.tax,
    required this.byPayment,
    required this.byType,
    required this.voids,
    required this.refunds,
    required this.discountsByStaff,
  });

  final String businessDate;
  final int paid;
  final int voidCount;
  final int openCount;
  final String gross;
  final String discounts;
  final String serviceCharge;
  final String roundOff;
  final String net;
  final String tips;
  final String cashExpected;
  final List<TaxLine> tax;
  final List<NamedAmount> byPayment;
  final List<NamedAmount> byType;
  final NamedAmount voids;
  final NamedAmount refunds;
  final List<NamedAmount> discountsByStaff;

  static NamedAmount _named(Object? raw, String label) {
    final m = raw is Map ? raw : const <dynamic, dynamic>{};
    return NamedAmount(
      label: label,
      count: (m['count'] as num?)?.toInt() ?? 0,
      amount: _money(m['amount']),
    );
  }

  static List<NamedAmount> _list(Object? raw, String Function(Map) label) {
    if (raw is! List) return const [];
    return [
      for (final row in raw.cast<Map>())
        NamedAmount(
          label: label(row),
          count: (row['count'] as num?)?.toInt() ?? 0,
          amount: _money(row['amount']),
        ),
    ];
  }

  factory DaySummary.fromJson(Map j) {
    final orders = j['orders'] is Map ? j['orders'] as Map : const <dynamic, dynamic>{};
    return DaySummary(
      businessDate: j['businessDate'] as String? ?? '',
      paid: (orders['paid'] as num?)?.toInt() ?? 0,
      voidCount: (orders['void'] as num?)?.toInt() ?? 0,
      openCount: (orders['open'] as num?)?.toInt() ?? 0,
      gross: _money(j['gross']),
      discounts: _money(j['discounts']),
      serviceCharge: _money(j['serviceCharge']),
      roundOff: _money(j['roundOff']),
      net: _money(j['net']),
      tips: _money(j['tips']),
      cashExpected: _money(j['cashExpected']),
      tax: [
        for (final t in (j['tax'] as List? ?? const [])) TaxLine.fromJson(t as Map),
      ],
      byPayment: _list(j['byPayment'], (m) => '${m['method']}'),
      byType: _list(j['byType'], (m) => '${m['type']}'),
      voids: _named(j['voids'], 'Voids'),
      refunds: _named(j['refunds'], 'Refunds'),
      discountsByStaff: _list(j['discountsByStaff'], (m) => '${m['name']}'),
    );
  }
}

class TaxLine {
  const TaxLine({required this.name, required this.rate, required this.amount});

  final String name;
  final String rate;
  final String amount;

  factory TaxLine.fromJson(Map j) => TaxLine(
        name: j['name'] as String? ?? '',
        rate: _money(j['rate']),
        amount: _money(j['amount']),
      );
}

/// One saved day close (Z report) in the history list.
class DayCloseRow {
  const DayCloseRow({
    required this.id,
    required this.businessDate,
    required this.kind,
    this.cashCounted,
    this.cashExpected,
  });

  final String id;
  final String businessDate;
  final String kind;
  final String? cashCounted;
  final String? cashExpected;

  factory DayCloseRow.fromJson(Map j) => DayCloseRow(
        id: j['id'] as String,
        businessDate: j['businessDate'] as String? ?? '',
        kind: j['kind'] as String? ?? 'Z',
        cashCounted: j['cashCounted'] == null ? null : _money(j['cashCounted']),
        cashExpected: j['cashExpected'] == null ? null : _money(j['cashExpected']),
      );
}

class DayCloseRepository {
  DayCloseRepository(this._dio);
  final Dio _dio;

  /// Live shift totals for the current business date. Nothing is saved.
  Future<DaySummary> xReport() async {
    final res = await _dio.get('/reports/x');
    return DaySummary.fromJson(res.data as Map);
  }

  /// Closes the business date. Throws 409 OPEN_ORDERS_EXIST with a count unless [force].
  Future<void> closeDay({required String cashCounted, bool force = false}) =>
      _dio.post('/reports/z', data: {'cashCounted': cashCounted, if (force) 'force': true});

  Future<List<DayCloseRow>> dayCloses() async {
    final res = await _dio.get('/reports/day-closes');
    final raw = res.data is Map ? res.data['data'] : res.data;
    return (raw as List).cast<Map>().map(DayCloseRow.fromJson).toList();
  }
}

final xReportProvider = FutureProvider<DaySummary>(
  (ref) => ref.watch(dayCloseRepositoryProvider).xReport(),
);

final dayClosesProvider = FutureProvider<List<DayCloseRow>>(
  (ref) => ref.watch(dayCloseRepositoryProvider).dayCloses(),
);
