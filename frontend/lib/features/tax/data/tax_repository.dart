import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';

final taxRepositoryProvider = Provider<TaxRepository>(
  (ref) => TaxRepository(ref.watch(dioProvider)),
);

/// One part of a tax rate, such as CGST 2.5 in a 5% GST class.
class TaxComponent {
  const TaxComponent({required this.name, required this.rate});

  final String name;
  final double rate;

  factory TaxComponent.fromJson(Map j) => TaxComponent(
        name: j['name'] as String,
        rate: double.tryParse(j['rate']?.toString() ?? '') ?? 0,
      );

  Map<String, dynamic> toJson() => {'name': name, 'rate': rate.toStringAsFixed(2)};
}

class TaxClass {
  const TaxClass({
    required this.id,
    required this.code,
    required this.name,
    required this.rate,
    this.isLiquor = false,
    this.inclusive = false,
    this.components = const [],
  });

  final String id;
  final String code;
  final String name;

  /// Percent, for example 5 for 5%.
  final double rate;
  final bool isLiquor;

  /// True when the shelf price already contains the tax.
  final bool inclusive;
  final List<TaxComponent> components;

  factory TaxClass.fromJson(Map j) => TaxClass(
        id: j['id'] as String,
        code: j['code'] as String? ?? '',
        name: j['name'] as String,
        rate: double.tryParse(j['rate']?.toString() ?? '') ?? 0,
        isLiquor: j['isLiquor'] as bool? ?? false,
        inclusive: j['inclusive'] as bool? ?? false,
        components: [
          for (final c in (j['components'] as List? ?? const [])) TaxComponent.fromJson(c as Map),
        ],
      );
}

/// Service charge, rounding and invoice numbering for the outlet.
class OutletSettings {
  const OutletSettings({
    this.serviceChargePercent = 0,
    this.serviceChargeTypes = const [],
    this.roundingMode = 'NONE',
    this.orderPrefix = 'ORD',
    this.invoicePrefix = 'INV',
    this.countryCode = 'IN',
  });

  final double serviceChargePercent;
  final List<String> serviceChargeTypes;
  final String roundingMode;
  final String orderPrefix;
  final String invoicePrefix;
  final String countryCode;

  OutletSettings copyWith({
    double? serviceChargePercent,
    List<String>? serviceChargeTypes,
    String? roundingMode,
    String? orderPrefix,
    String? invoicePrefix,
    String? countryCode,
  }) =>
      OutletSettings(
        serviceChargePercent: serviceChargePercent ?? this.serviceChargePercent,
        serviceChargeTypes: serviceChargeTypes ?? this.serviceChargeTypes,
        roundingMode: roundingMode ?? this.roundingMode,
        orderPrefix: orderPrefix ?? this.orderPrefix,
        invoicePrefix: invoicePrefix ?? this.invoicePrefix,
        countryCode: countryCode ?? this.countryCode,
      );

  factory OutletSettings.fromJson(Map j) => OutletSettings(
        serviceChargePercent: double.tryParse(j['serviceChargePercent']?.toString() ?? '') ?? 0,
        serviceChargeTypes: [
          for (final v in (j['serviceChargeTypes'] as List? ?? const [])) v.toString(),
        ],
        roundingMode: j['roundingMode'] as String? ?? 'NONE',
        orderPrefix: j['orderPrefix'] as String? ?? 'ORD',
        invoicePrefix: j['invoicePrefix'] as String? ?? 'INV',
        countryCode: j['countryCode'] as String? ?? 'IN',
      );

  Map<String, dynamic> toJson() => {
        'serviceChargePercent': serviceChargePercent.toStringAsFixed(2),
        'serviceChargeTypes': serviceChargeTypes,
        'roundingMode': roundingMode,
        'orderPrefix': orderPrefix,
        'invoicePrefix': invoicePrefix,
        'countryCode': countryCode,
      };
}

class TaxRepository {
  TaxRepository(this._dio);
  final Dio _dio;

  static List<Map> _rows(dynamic body) {
    final raw = body is Map ? body['data'] : body;
    return (raw as List).cast<Map>();
  }

  Future<List<TaxClass>> taxClasses() async {
    final res = await _dio.get('/tax-classes');
    return _rows(res.data).map(TaxClass.fromJson).toList();
  }

  Future<void> createTaxClass(Map<String, dynamic> body) => _dio.post('/tax-classes', data: body);

  Future<void> updateTaxClass(String id, Map<String, dynamic> body) =>
      _dio.patch('/tax-classes/$id', data: body);

  /// Throws 409 TAX_CLASS_IN_USE while active products or categories use it.
  Future<void> deleteTaxClass(String id) => _dio.delete('/tax-classes/$id');

  Future<OutletSettings> outletSettings() async {
    final res = await _dio.get('/outlet-settings');
    return OutletSettings.fromJson(res.data as Map);
  }

  Future<void> saveOutletSettings(OutletSettings settings) =>
      _dio.put('/outlet-settings', data: settings.toJson());

  /// Legacy single global rate, still used for products without a tax class.
  Future<double> globalTax() async {
    final res = await _dio.get('/tax/global');
    return double.parse(res.data['percentage'].toString());
  }

  Future<void> saveGlobalTax(double percentage) =>
      _dio.put('/tax/global', data: {'percentage': percentage});
}

final taxClassesProvider = FutureProvider<List<TaxClass>>(
  (ref) => ref.watch(taxRepositoryProvider).taxClasses(),
);

final outletSettingsProvider = FutureProvider<OutletSettings>(
  (ref) => ref.watch(taxRepositoryProvider).outletSettings(),
);

final globalTaxProvider = FutureProvider<double>(
  (ref) => ref.watch(taxRepositoryProvider).globalTax(),
);
