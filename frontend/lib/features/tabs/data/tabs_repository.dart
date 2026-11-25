import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/providers.dart';
import '../../pos/data/pos_models.dart';
import 'tabs_models.dart';

final tabsRepositoryProvider = Provider<TabsRepository>(
  (ref) => TabsRepository(ref.watch(dioProvider)),
);

/// Bar tab and bottle locker calls (PLAN 1.7). Dio errors are rethrown as
/// [ApiError] with the server `code` and `details`.
class TabsRepository {
  TabsRepository(this._dio);

  final Dio _dio;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw ApiError.fromDio(e);
    }
  }

  static Map<String, dynamic> _query(Map<String, dynamic> raw) {
    raw.removeWhere((_, v) => v == null);
    return raw;
  }

  // --- tabs ------------------------------------------------------------------

  /// GET /tabs. [scope] is `today` by default. Pass [openedById] to filter by
  /// bartender. Status filtering is done by the screen.
  Future<TabsPage> tabs({String scope = 'today', String? status, String? openedById}) =>
      _guard(() async {
        final r = await _dio.get<dynamic>(
          '/tabs',
          queryParameters: _query({'scope': scope, 'status': status, 'openedById': openedById}),
        );
        return TabsPage.fromJson(asMap(r.data));
      });

  /// GET /tabs/:id
  Future<TabView> tab(String id) => _guard(() async {
        final r = await _dio.get<dynamic>('/tabs/$id');
        return TabView.fromJson(asMap(r.data));
      });

  /// POST /tabs. Creates the tab and its BAR_COUNTER order.
  Future<TabView> openTab(OpenTabRequest body) => _guard(() async {
        final r = await _dio.post<dynamic>('/tabs', data: body.toJson());
        return TabView.fromJson(asMap(r.data));
      });

  /// PUT /tabs/:id
  Future<TabView> updateTab(String id, TabEditRequest body) => _guard(() async {
        final r = await _dio.put<dynamic>('/tabs/$id', data: body.toJson());
        return TabView.fromJson(asMap(r.data));
      });

  /// POST /tabs/:id/move-to-table. Throws `TABLE_OCCUPIED` when taken.
  Future<TabView> moveToTable(String id, {required String tableId}) => _guard(() async {
        final r = await _dio.post<dynamic>('/tabs/$id/move-to-table', data: {'tableId': tableId});
        return TabView.fromJson(asMap(r.data));
      });

  /// POST /tabs/:id/close. Bills the order and applies any cash deposit.
  Future<TabCloseResult> closeTab(String id) => _guard(() async {
        final r = await _dio.post<dynamic>('/tabs/$id/close');
        return TabCloseResult.fromJson(asMap(r.data));
      });

  /// POST /tabs/:id/void. Only for empty tabs (`TAB_NOT_EMPTY` otherwise).
  Future<TabView> voidTab(String id, {required String reason}) => _guard(() async {
        final r = await _dio.post<dynamic>('/tabs/$id/void', data: {'reason': reason});
        return TabView.fromJson(asMap(r.data));
      });

  // --- bottle locker ---------------------------------------------------------

  /// GET /locker?status=&search=
  Future<List<LockerView>> lockers({String? status, String? search}) => _guard(() async {
        final r = await _dio.get<dynamic>(
          '/locker',
          queryParameters: _query({'status': status, 'search': search}),
        );
        return [for (final l in asMaps(r.data)) LockerView.fromJson(l)];
      });

  /// POST /locker
  Future<LockerView> storeBottle(LockerCreateRequest body) => _guard(() async {
        final r = await _dio.post<dynamic>('/locker', data: body.toJson());
        return LockerView.fromJson(asMap(r.data));
      });

  /// POST /locker/:id/serve. Throws `NOT_ENOUGH_LEFT` or `LOCKER_EXPIRED`.
  Future<LockerView> serveBottle(String id, {required int ml}) => _guard(() async {
        final r = await _dio.post<dynamic>('/locker/$id/serve', data: {'ml': ml});
        return LockerView.fromJson(asMap(r.data));
      });

  /// PUT /locker/:id
  Future<LockerView> updateLocker(String id, LockerEditRequest body) => _guard(() async {
        final r = await _dio.put<dynamic>('/locker/$id', data: body.toJson());
        return LockerView.fromJson(asMap(r.data));
      });

  /// DELETE /locker/:id with a reason. The entry becomes REMOVED.
  Future<LockerView> removeLocker(String id, {required String reason}) => _guard(() async {
        final r = await _dio.delete<dynamic>('/locker/$id', data: {'reason': reason});
        return LockerView.fromJson(asMap(r.data));
      });
}
