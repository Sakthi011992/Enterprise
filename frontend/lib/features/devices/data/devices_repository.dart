import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_billing/core/providers.dart';
import 'package:pos_billing/features/personas/data/admin_api.dart';

/// DeviceType values from plan 1.3, in the order the register form shows them.
const deviceTypes = ['POS_TABLET', 'KDS', 'TV', 'KIOSK', 'PRINTER', 'PHONE'];

String deviceTypeLabel(String type) {
  return switch (type) {
    'POS_TABLET' => 'POS tablet',
    'KDS' => 'Kitchen display (KDS)',
    'TV' => 'TV display',
    'KIOSK' => 'Kiosk',
    'PRINTER' => 'Printer',
    'PHONE' => 'Phone',
    _ => type,
  };
}

class Device {
  const Device({
    required this.id,
    required this.outletId,
    required this.name,
    required this.type,
    this.lastSeenAt,
    required this.isActive,
  });

  final String id;
  final String outletId;
  final String name;
  final String type;
  final DateTime? lastSeenAt;
  final bool isActive;

  factory Device.fromJson(Map<String, dynamic> json) => Device(
        id: json['id'] as String,
        outletId: json['outletId'] as String,
        name: json['name'] as String,
        type: json['type'] as String,
        lastSeenAt: json['lastSeenAt'] == null ? null : DateTime.tryParse(json['lastSeenAt'] as String),
        isActive: json['isActive'] != false,
      );
}

/// Response of POST /devices. `deviceKey` is returned once and never again.
class RegisteredDevice {
  const RegisteredDevice({required this.device, required this.deviceKey});

  final Device device;
  final String deviceKey;

  factory RegisteredDevice.fromJson(Map<String, dynamic> json) => RegisteredDevice(
        device: Device.fromJson(json['device'] as Map<String, dynamic>),
        deviceKey: json['deviceKey'] as String,
      );
}

final devicesRepositoryProvider = Provider<DevicesRepository>(
  (ref) => DevicesRepository(ref.watch(dioProvider)),
);

class DevicesRepository {
  DevicesRepository(this._dio);
  final Dio _dio;

  Future<List<Device>> list(String outletId) async {
    final res = await _dio.get('/devices', queryParameters: {'outletId': outletId});
    return listFrom(res.data).map(Device.fromJson).toList();
  }

  Future<RegisteredDevice> register({
    required String outletId,
    required String name,
    required String type,
  }) async {
    final res = await _dio.post('/devices', data: {
      'outletId': outletId,
      'name': name,
      'type': type,
    });
    return RegisteredDevice.fromJson(res.data as Map<String, dynamic>);
  }

  /// Soft delete on the server: the device is marked inactive and its key stops working.
  Future<void> deactivate(String id) => _dio.delete('/devices/$id');
}

final devicesListProvider = FutureProvider.autoDispose.family<List<Device>, String>(
  (ref, outletId) => ref.watch(devicesRepositoryProvider).list(outletId),
);
