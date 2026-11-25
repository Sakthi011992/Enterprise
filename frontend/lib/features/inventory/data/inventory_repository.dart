import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/providers.dart';
import '../../../core/files/pick_file.dart';
import 'inventory_models.dart';
import 'json_read.dart';
import 'offline_count_queue.dart';

final inventoryRepositoryProvider = Provider<InventoryRepository>(
  (ref) => InventoryRepository(ref.watch(dioProvider)),
);

/// Filter for the stock item list (`GET /stock/items`). A record, so Riverpod
/// family keys compare by value.
typedef StockItemFilter = ({String? locationId, String? status, bool liquor});

/// Every inventory call (PLAN 1.7, "Inventory"). Dio errors are rethrown as
/// [ApiError] with the server `code` and `details`.
class InventoryRepository implements CountLineGateway {
  InventoryRepository(this._dio);

  final Dio _dio;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw ApiError.fromDio(e);
    }
  }

  // --- summary and locations ------------------------------------------------

  /// GET /inventory/summary
  Future<InventorySummary> summary() => _guard(() async {
        final r = await _dio.get<dynamic>('/inventory/summary');
        return InventorySummary.fromJson(jsonMap(r.data));
      });

  /// GET /stock/locations
  Future<List<LocationView>> locations() => _guard(() async {
        final r = await _dio.get<dynamic>('/stock/locations');
        return [for (final l in jsonMaps(r.data)) LocationView.fromJson(l)];
      });

  /// POST /stock/locations
  Future<LocationView> createLocation(LocationView body) => _guard(() async {
        final r = await _dio.post<dynamic>('/stock/locations', data: body.toJson());
        return LocationView.fromJson(jsonMap(r.data));
      });

  /// PUT /stock/locations/:id
  Future<LocationView> updateLocation(String id, LocationView body) => _guard(() async {
        final r = await _dio.put<dynamic>('/stock/locations/$id', data: body.toJson());
        return LocationView.fromJson(jsonMap(r.data));
      });

  // --- stock items ----------------------------------------------------------

  /// GET /stock/items
  Future<List<StockItemRow>> stockItems(StockItemFilter filter) => _guard(() async {
        final r = await _dio.get<dynamic>('/stock/items', queryParameters: {
          if (filter.locationId != null) 'locationId': filter.locationId,
          if (filter.status != null) 'status': filter.status,
          if (filter.liquor) 'liquor': true,
        });
        return [for (final i in jsonMaps(r.data)) StockItemRow.fromJson(i)];
      });

  /// GET /stock/items/:id
  Future<StockItemDetail> stockItem(String id) => _guard(() async {
        final r = await _dio.get<dynamic>('/stock/items/$id');
        return StockItemDetail.fromJson(jsonMap(r.data));
      });

  /// POST /stock/items with optional opening stock per location.
  Future<StockItemDetail> createStockItem(
    StockItemInput input, {
    List<({String locationId, num qty})> opening = const [],
  }) =>
      _guard(() async {
        final body = input.toJson()
          ..['opening'] = [
            for (final o in opening) {'locationId': o.locationId, 'qty': o.qty},
          ];
        final r = await _dio.post<dynamic>('/stock/items', data: body);
        return StockItemDetail.fromJson(jsonMap(r.data));
      });

  /// PUT /stock/items/:id
  Future<StockItemDetail> updateStockItem(String id, StockItemInput input) => _guard(() async {
        final r = await _dio.put<dynamic>('/stock/items/$id', data: input.toJson());
        return StockItemDetail.fromJson(jsonMap(r.data));
      });

  /// PUT /stock/items/:id/par
  Future<StockItemDetail> setPar(String id, List<({String locationId, num parLevel})> levels) =>
      _guard(() async {
        final r = await _dio.put<dynamic>('/stock/items/$id/par', data: {
          'levels': [for (final l in levels) {'locationId': l.locationId, 'parLevel': l.parLevel}],
        });
        return StockItemDetail.fromJson(jsonMap(r.data));
      });

  /// GET /stock/items/:id/movements
  Future<List<MovementRow>> movements(String stockItemId,
          {String? locationId, String? from, String? to, int limit = 100}) =>
      _guard(() async {
        final r = await _dio.get<dynamic>('/stock/items/$stockItemId/movements', queryParameters: {
          if (locationId != null) 'locationId': locationId,
          if (from != null) 'from': from,
          if (to != null) 'to': to,
          'limit': limit,
        });
        return [for (final m in jsonMaps(r.data)) MovementRow.fromJson(m)];
      });

  // --- transfers ------------------------------------------------------------

  /// GET /stock/transfers
  Future<List<TransferView>> transfers({String? from, String? to}) => _guard(() async {
        final r = await _dio.get<dynamic>('/stock/transfers', queryParameters: {
          if (from != null) 'from': from,
          if (to != null) 'to': to,
        });
        return [for (final t in jsonMaps(r.data)) TransferView.fromJson(t)];
      });

  /// POST /stock/transfers. Quantities are base units.
  Future<TransferView> createTransfer({
    required String fromLocationId,
    required String toLocationId,
    String? note,
    required List<({String stockItemId, num qty})> lines,
  }) =>
      _guard(() async {
        final r = await _dio.post<dynamic>('/stock/transfers', data: {
          'fromLocationId': fromLocationId,
          'toLocationId': toLocationId,
          'note': note,
          'lines': [for (final l in lines) {'stockItemId': l.stockItemId, 'qty': l.qty}],
        });
        return TransferView.fromJson(jsonMap(r.data));
      });

  // --- stock counts ---------------------------------------------------------

  /// GET /stock/counts
  Future<List<CountSummary>> counts({String? status, String? locationId}) => _guard(() async {
        final r = await _dio.get<dynamic>('/stock/counts', queryParameters: {
          if (status != null) 'status': status,
          if (locationId != null) 'locationId': locationId,
        });
        return [for (final c in jsonMaps(r.data)) CountSummary.fromJson(c)];
      });

  /// POST /stock/counts. Throws `COUNT_ALREADY_OPEN` with `details.countId`
  /// when the location already has an open count.
  Future<CountView> startCount(String locationId) => _guard(() async {
        final r = await _dio.post<dynamic>('/stock/counts', data: {'locationId': locationId});
        return CountView.fromJson(jsonMap(r.data));
      });

  /// GET /stock/counts/:id
  Future<CountView> count(String id) => _guard(() async {
        final r = await _dio.get<dynamic>('/stock/counts/$id');
        return CountView.fromJson(jsonMap(r.data));
      });

  /// PUT /stock/counts/:id/lines. Idempotent, so offline replays are safe.
  @override
  Future<CountView> saveCountLines(String countId, List<CountLineInput> lines) => _guard(() async {
        final r = await _dio.put<dynamic>('/stock/counts/$countId/lines', data: {
          'lines': [for (final l in lines) l.toJson()],
        });
        return CountView.fromJson(jsonMap(r.data));
      });

  /// POST /stock/counts/:id/submit
  Future<CountView> submitCount(String id) => _guard(() async {
        final r = await _dio.post<dynamic>('/stock/counts/$id/submit');
        return CountView.fromJson(jsonMap(r.data));
      });

  /// POST /stock/counts/:id/post
  Future<CountView> postCount(String id) => _guard(() async {
        final r = await _dio.post<dynamic>('/stock/counts/$id/post');
        return CountView.fromJson(jsonMap(r.data));
      });

  /// POST /stock/counts/:id/cancel
  Future<CountView> cancelCount(String id) => _guard(() async {
        final r = await _dio.post<dynamic>('/stock/counts/$id/cancel');
        return CountView.fromJson(jsonMap(r.data));
      });

  // --- wastage and uploads --------------------------------------------------

  /// GET /stock/wastage
  Future<WastageList> wastage({String? from, String? to, String? locationId}) => _guard(() async {
        final r = await _dio.get<dynamic>('/stock/wastage', queryParameters: {
          if (from != null) 'from': from,
          if (to != null) 'to': to,
          if (locationId != null) 'locationId': locationId,
        });
        return WastageList.fromJson(jsonMap(r.data));
      });

  /// POST /stock/wastage. `qty` is base units. Throws `PHOTO_REQUIRED`,
  /// `INSUFFICIENT_STOCK` (details `onHand`, `onHandDisplay`) or `INVALID_REASON`.
  Future<WastageView> logWastage({
    required String locationId,
    required String stockItemId,
    required num qty,
    required String reason,
    String? note,
    String? photoUrl,
  }) =>
      _guard(() async {
        final r = await _dio.post<dynamic>('/stock/wastage', data: {
          'locationId': locationId,
          'stockItemId': stockItemId,
          'qty': qty,
          'reason': reason,
          'note': note,
          'photoUrl': photoUrl,
        });
        return WastageView.fromJson(jsonMap(r.data));
      });

  /// POST /stock/uploads (multipart `file`). Returns the stored URL.
  Future<String> uploadFile(PickedFileData file) => _guard(() async {
        final form = FormData.fromMap({
          'file': MultipartFile.fromBytes(file.bytes, filename: file.name),
        });
        final r = await _dio.post<dynamic>('/stock/uploads', data: form);
        return jsonStr(jsonMap(r.data), 'url');
      });

  // --- variance, kegs -------------------------------------------------------

  /// GET /stock/variance
  Future<VarianceReport> variance({
    String? locationId,
    required String from,
    required String to,
    bool liquor = true,
  }) =>
      _guard(() async {
        final r = await _dio.get<dynamic>('/stock/variance', queryParameters: {
          if (locationId != null) 'locationId': locationId,
          'from': from,
          'to': to,
          'liquor': liquor,
        });
        return VarianceReport.fromJson(jsonMap(r.data));
      });

  /// GET /stock/kegs
  Future<List<KegRow>> kegs() => _guard(() async {
        final r = await _dio.get<dynamic>('/stock/kegs');
        return [for (final k in jsonMaps(r.data)) KegRow.fromJson(k)];
      });

  // --- recipes (product scoped) ---------------------------------------------

  /// GET /products/:id/recipes
  Future<List<RecipeView>> recipes(String productId) => _guard(() async {
        final r = await _dio.get<dynamic>('/products/$productId/recipes');
        return [for (final x in jsonMaps(r.data)) RecipeView.fromJson(x)];
      });

  /// PUT /products/:id/recipes. Replaces every recipe of the product.
  Future<List<RecipeView>> saveRecipes(String productId, List<RecipeInput> recipes) =>
      _guard(() async {
        final r = await _dio.put<dynamic>('/products/$productId/recipes', data: {
          'recipes': [for (final x in recipes) x.toJson()],
        });
        return [for (final x in jsonMaps(r.data)) RecipeView.fromJson(x)];
      });
}

/// Stock locations for the current outlet.
final inventoryLocationsProvider = FutureProvider<List<LocationView>>(
  (ref) => ref.watch(inventoryRepositoryProvider).locations(),
);

final inventorySummaryProvider = FutureProvider<InventorySummary>(
  (ref) => ref.watch(inventoryRepositoryProvider).summary(),
);

/// Stock items for a filter. Use a record key, for example
/// `stockItemsProvider((locationId: null, status: null, liquor: false))`.
final stockItemsProvider = FutureProvider.family<List<StockItemRow>, StockItemFilter>(
  (ref, filter) => ref.watch(inventoryRepositoryProvider).stockItems(filter),
);
