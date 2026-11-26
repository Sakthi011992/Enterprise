import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/providers.dart';
import '../../pos/data/pos_models.dart';
import 'guest_models.dart';
import 'mock_guest_requests_repository.dart';

/// `--dart-define=GUEST_MOCK=true` runs the staff guest screens on in-memory data.
const guestMockEnabled = bool.fromEnvironment('GUEST_MOCK');

/// Every staff call for guest ordering (PLAN 2.7).
abstract interface class GuestRequestsRepository {
  /// GET /guest-requests?status=PENDING (oldest first).
  Future<List<GuestRequest>> pendingRequests();

  /// POST /guest-requests/:id/claim
  Future<GuestRequest> claim(String id);

  /// POST /guest-requests/:id/confirm `{ items? }`. [items] null = as placed.
  Future<void> confirm(String id, {List<GuestLine>? items});

  /// POST /guest-requests/:id/reject `{ reason }`
  Future<void> reject(String id, {required String reason});

  /// GET /service-requests?status=OPEN (also returns ACKNOWLEDGED until done).
  Future<List<ServiceRequest>> openServiceRequests();

  /// POST /service-requests/:id/ack
  Future<ServiceRequest> acknowledge(String id);

  /// POST /service-requests/:id/done
  Future<void> done(String id);

  /// GET /settings/guest
  Future<GuestConfig> config();

  /// PUT /settings/guest
  Future<GuestConfig> saveConfig(GuestConfig config, {String? newStaticOtp});

  /// GET /tables/:id/guest-pin. Null when the table has no PIN.
  Future<String?> guestPin(String tableId);

  /// POST /tables/:id/qr/rotate
  Future<void> rotateQr(String tableId);

  /// GET /tables/qr-sheet?areaId= (PDF bytes)
  Future<Uint8List> qrSheet({String? areaId});
}

final guestRequestsRepositoryProvider = Provider<GuestRequestsRepository>((ref) {
  if (guestMockEnabled) {
    final userId = ref.read(sessionProvider).session?.user.id ?? 'me';
    return MockGuestRequestsRepository(currentUserId: userId);
  }
  return HttpGuestRequestsRepository(ref.watch(dioProvider));
});

/// Real implementation against the staff API (PLAN 2.7).
class HttpGuestRequestsRepository implements GuestRequestsRepository {
  HttpGuestRequestsRepository(this._dio);

  final Dio _dio;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw ApiError.fromDio(e);
    }
  }

  static List<Map<String, dynamic>> _rows(Object? body) =>
      asMaps(body is Map ? body['data'] ?? body['items'] : body);

  @override
  Future<List<GuestRequest>> pendingRequests() => _guard(() async {
        final r = await _dio.get<dynamic>('/guest-requests',
            queryParameters: {'status': GuestRequestStatuses.pending});
        return [for (final j in _rows(r.data)) GuestRequest.fromJson(j)];
      });

  @override
  Future<GuestRequest> claim(String id) => _guard(() async {
        final r = await _dio.post<dynamic>('/guest-requests/$id/claim');
        return GuestRequest.fromJson(asMap(r.data));
      });

  @override
  Future<void> confirm(String id, {List<GuestLine>? items}) => _guard(() async {
        await _dio.post<dynamic>('/guest-requests/$id/confirm', data: {
          if (items != null) 'items': [for (final l in items) l.toConfirmJson()],
        });
      });

  @override
  Future<void> reject(String id, {required String reason}) => _guard(() async {
        await _dio.post<dynamic>('/guest-requests/$id/reject', data: {'reason': reason});
      });

  @override
  Future<List<ServiceRequest>> openServiceRequests() => _guard(() async {
        final r = await _dio.get<dynamic>('/service-requests',
            queryParameters: {'status': ServiceRequestStatuses.open});
        return [for (final j in _rows(r.data)) ServiceRequest.fromJson(j)];
      });

  @override
  Future<ServiceRequest> acknowledge(String id) => _guard(() async {
        final r = await _dio.post<dynamic>('/service-requests/$id/ack');
        return ServiceRequest.fromJson(asMap(r.data));
      });

  @override
  Future<void> done(String id) => _guard(() async {
        await _dio.post<dynamic>('/service-requests/$id/done');
      });

  @override
  Future<GuestConfig> config() => _guard(() async {
        final r = await _dio.get<dynamic>('/settings/guest');
        return GuestConfig.fromJson(asMap(r.data));
      });

  @override
  Future<GuestConfig> saveConfig(GuestConfig config, {String? newStaticOtp}) =>
      _guard(() async {
        final r = await _dio.put<dynamic>('/settings/guest',
            data: config.toJson(newStaticOtp: newStaticOtp));
        final body = asMap(r.data);
        return body.isEmpty ? config : GuestConfig.fromJson(body);
      });

  @override
  Future<String?> guestPin(String tableId) => _guard(() async {
        final r = await _dio.get<dynamic>('/tables/$tableId/guest-pin');
        final pin = asMap(r.data)['pin'];
        return pin == null || '$pin'.isEmpty ? null : '$pin';
      });

  @override
  Future<void> rotateQr(String tableId) => _guard(() async {
        await _dio.post<dynamic>('/tables/$tableId/qr/rotate');
      });

  @override
  Future<Uint8List> qrSheet({String? areaId}) => _guard(() async {
        final r = await _dio.get<List<int>>(
          '/tables/qr-sheet',
          queryParameters: {if (areaId != null) 'areaId': areaId},
          options: Options(responseType: ResponseType.bytes),
        );
        return Uint8List.fromList(r.data ?? const []);
      });
}
