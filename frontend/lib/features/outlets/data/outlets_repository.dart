import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_billing/core/providers.dart';
import 'package:pos_billing/features/personas/data/admin_api.dart';

class Outlet {
  const Outlet({
    required this.id,
    required this.name,
    required this.code,
    this.address,
    required this.timezone,
    required this.isActive,
  });

  final String id;
  final String name;
  final String code;
  final String? address;
  final String timezone;
  final bool isActive;

  factory Outlet.fromJson(Map<String, dynamic> json) => Outlet(
        id: json['id'] as String,
        name: json['name'] as String,
        code: (json['code'] as String?) ?? '',
        address: json['address'] as String?,
        timezone: (json['timezone'] as String?) ?? 'Asia/Kolkata',
        isActive: json['isActive'] != false,
      );
}

final outletsRepositoryProvider = Provider<OutletsRepository>(
  (ref) => OutletsRepository(ref.watch(dioProvider)),
);

class OutletsRepository {
  OutletsRepository(this._dio);
  final Dio _dio;

  /// admin.settings VIEW sees every outlet in the tenant; others see only their own.
  Future<List<Outlet>> list() async {
    final res = await _dio.get('/outlets');
    return listFrom(res.data).map(Outlet.fromJson).toList();
  }

  Future<Outlet> create(Map<String, dynamic> body) async {
    final res = await _dio.post('/outlets', data: body);
    return Outlet.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Outlet> update(String id, Map<String, dynamic> body) async {
    final res = await _dio.patch('/outlets/$id', data: body);
    return Outlet.fromJson(res.data as Map<String, dynamic>);
  }
}

final outletsListProvider = FutureProvider.autoDispose<List<Outlet>>(
  (ref) => ref.watch(outletsRepositoryProvider).list(),
);
