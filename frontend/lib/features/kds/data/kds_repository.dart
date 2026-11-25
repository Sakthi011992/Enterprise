import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/providers.dart';
import '../../pos/data/pos_models.dart';
import 'kds_models.dart';

final kdsRepositoryProvider = Provider<KdsRepository>(
  (ref) => KdsRepository(ref.watch(dioProvider)),
);

/// Kitchen display calls (PLAN 1.7 "KDS"). Dio errors are rethrown as
/// [ApiError]. `KDS_BAD_STATE` and `RECALL_TOO_LATE` arrive as codes.
class KdsRepository {
  KdsRepository(this._dio);

  final Dio _dio;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw ApiError.fromDio(e);
    }
  }

  /// GET /kds/tickets. [station] is `ALL`, `BAR`, `KITCHEN`, `GRILL`, ...
  /// [view] is `active` (NEW, PREPARING, READY) or `done` (SERVED, 2 h).
  Future<KdsBoard> board({String station = 'ALL', String view = 'active'}) => _guard(() async {
        final r = await _dio.get<dynamic>(
          '/kds/tickets',
          queryParameters: {'station': station, 'view': view},
        );
        return KdsBoard.fromJson(asMap(r.data), receivedAt: DateTime.now());
      });

  /// POST /kds/tickets/:id/start (NEW to PREPARING)
  Future<KdsTicket> start(String ticketId) => _ticketAction(ticketId, 'start');

  /// POST /kds/tickets/:id/bump (NEW or PREPARING to READY, notifies the waiter)
  Future<KdsTicket> bump(String ticketId) => _ticketAction(ticketId, 'bump');

  /// POST /kds/tickets/:id/recall (READY or SERVED to PREPARING)
  Future<KdsTicket> recall(String ticketId) => _ticketAction(ticketId, 'recall');

  /// POST /kds/tickets/:id/served (READY to SERVED)
  Future<KdsTicket> served(String ticketId) => _ticketAction(ticketId, 'served');

  Future<KdsTicket> _ticketAction(String ticketId, String action) => _guard(() async {
        final r = await _dio.post<dynamic>('/kds/tickets/$ticketId/$action');
        return KdsTicket.fromJson(asMap(r.data));
      });

  /// GET /kds/ready?mine=true|false. READY tickets of the outlet.
  Future<List<ReadyItem>> ready({bool mine = false}) => _guard(() async {
        final r = await _dio.get<dynamic>(
          '/kds/ready',
          queryParameters: mine ? {'mine': 'true'} : null,
        );
        return [for (final row in asMaps(r.data)) ReadyItem.fromJson(row)];
      });

  /// GET /kds/stations
  Future<List<KdsStation>> stations() => _guard(() async {
        final r = await _dio.get<dynamic>('/kds/stations');
        return [for (final row in asMaps(r.data)) KdsStation.fromJson(row)];
      });
}
