import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/providers.dart';
import '../../inventory/data/json_read.dart';
import 'procurement_models.dart';

final procurementRepositoryProvider = Provider<ProcurementRepository>(
  (ref) => ProcurementRepository(ref.watch(dioProvider)),
);

/// Every procurement call (PLAN 1.7, "Procurement"). Dio errors are rethrown
/// as [ApiError] with the server `code` and `details`.
class ProcurementRepository {
  ProcurementRepository(this._dio);

  final Dio _dio;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw ApiError.fromDio(e);
    }
  }

  // --- vendors --------------------------------------------------------------

  /// GET /vendors
  Future<List<VendorView>> vendors({bool activeOnly = false}) => _guard(() async {
        final r = await _dio.get<dynamic>('/vendors', queryParameters: {
          if (activeOnly) 'active': true,
        });
        return [for (final v in jsonMaps(r.data)) VendorView.fromJson(v)];
      });

  /// POST /vendors, or PUT /vendors/:id when [id] is given.
  Future<VendorView> saveVendor(VendorView vendor, {String? id}) => _guard(() async {
        final r = id == null
            ? await _dio.post<dynamic>('/vendors', data: vendor.toJson())
            : await _dio.put<dynamic>('/vendors/$id', data: vendor.toJson());
        return VendorView.fromJson(jsonMap(r.data));
      });

  // --- purchase orders ------------------------------------------------------

  /// GET /purchase-orders
  Future<PoListPage> purchaseOrders({String? status, String? vendorId}) => _guard(() async {
        final r = await _dio.get<dynamic>('/purchase-orders', queryParameters: {
          if (status != null) 'status': status,
          if (vendorId != null) 'vendorId': vendorId,
        });
        return PoListPage.fromJson(jsonMap(r.data));
      });

  /// GET /purchase-orders/:id
  Future<PoView> purchaseOrder(String id) => _guard(() async {
        final r = await _dio.get<dynamic>('/purchase-orders/$id');
        return PoView.fromJson(jsonMap(r.data));
      });

  /// POST /purchase-orders. Throws `EMPTY_PO` when there are no lines.
  Future<PoView> createPurchaseOrder(Map<String, dynamic> body) => _guard(() async {
        final r = await _dio.post<dynamic>('/purchase-orders', data: body);
        return PoView.fromJson(jsonMap(r.data));
      });

  /// PUT /purchase-orders/:id. Editing a PENDING_APPROVAL PO returns it to DRAFT.
  Future<PoView> updatePurchaseOrder(String id, Map<String, dynamic> body) => _guard(() async {
        final r = await _dio.put<dynamic>('/purchase-orders/$id', data: body);
        return PoView.fromJson(jsonMap(r.data));
      });

  /// DELETE /purchase-orders/:id (drafts only).
  Future<void> deletePurchaseOrder(String id) => _guard(() async {
        await _dio.delete<dynamic>('/purchase-orders/$id');
      });

  /// POST /purchase-orders/:id/submit
  Future<PoView> submitPurchaseOrder(String id) => _poAction(id, 'submit');

  /// POST /purchase-orders/:id/approve
  Future<PoView> approvePurchaseOrder(String id) => _poAction(id, 'approve');

  /// POST /purchase-orders/:id/send. Auto-approves when the caller may approve.
  Future<PoView> sendPurchaseOrder(String id) => _poAction(id, 'send');

  /// POST /purchase-orders/:id/cancel
  Future<PoView> cancelPurchaseOrder(String id, String reason) => _guard(() async {
        final r = await _dio.post<dynamic>('/purchase-orders/$id/cancel', data: {'reason': reason});
        return PoView.fromJson(jsonMap(r.data));
      });

  Future<PoView> _poAction(String id, String action) => _guard(() async {
        final r = await _dio.post<dynamic>('/purchase-orders/$id/$action');
        return PoView.fromJson(jsonMap(r.data));
      });

  /// GET /purchase-orders/reorder-suggestions
  Future<List<ReorderSuggestion>> reorderSuggestions({String? locationId}) => _guard(() async {
        final r = await _dio.get<dynamic>('/purchase-orders/reorder-suggestions', queryParameters: {
          if (locationId != null) 'locationId': locationId,
        });
        return [for (final s in jsonMaps(r.data)) ReorderSuggestion.fromJson(s)];
      });

  /// POST /purchase-orders/reorder-request. One PENDING_APPROVAL PO per vendor.
  /// Throws `VENDOR_MISSING` (details `stockItemIds`) for lines with no vendor.
  Future<List<PoSummary>> reorderRequest({
    required String locationId,
    required List<({String stockItemId, num qty})> lines,
  }) =>
      _guard(() async {
        final r = await _dio.post<dynamic>('/purchase-orders/reorder-request', data: {
          'locationId': locationId,
          'lines': [for (final l in lines) {'stockItemId': l.stockItemId, 'qty': l.qty}],
        });
        return [for (final p in jsonMaps(jsonMap(r.data)['purchaseOrders'])) PoSummary.fromJson(p)];
      });

  // --- goods received -------------------------------------------------------

  /// GET /grns
  Future<List<GrnSummary>> grns({String? from, String? to, String? vendorId}) => _guard(() async {
        final r = await _dio.get<dynamic>('/grns', queryParameters: {
          if (from != null) 'from': from,
          if (to != null) 'to': to,
          if (vendorId != null) 'vendorId': vendorId,
        });
        return [for (final g in jsonMaps(r.data)) GrnSummary.fromJson(g)];
      });

  /// GET /grns/:id
  Future<GrnView> grn(String id) => _guard(() async {
        final r = await _dio.get<dynamic>('/grns/$id');
        return GrnView.fromJson(jsonMap(r.data));
      });

  /// POST /grns. With [poId] and no lines, lines come from the PO's outstanding qty.
  Future<GrnView> createGrn(Map<String, dynamic> body) => _guard(() async {
        final r = await _dio.post<dynamic>('/grns', data: body);
        return GrnView.fromJson(jsonMap(r.data));
      });

  /// PUT /grns/:id (draft only; `409 GRN_POSTED` otherwise).
  Future<GrnView> updateGrn(String id, Map<String, dynamic> body) => _guard(() async {
        final r = await _dio.put<dynamic>('/grns/$id', data: body);
        return GrnView.fromJson(jsonMap(r.data));
      });

  /// POST /grns/:id/post. May throw `INVOICE_NO_REQUIRED`, `PERMIT_REQUIRED`,
  /// or `INVALID_QTY` (details `line`, `field`).
  Future<GrnView> postGrn(String id) => _guard(() async {
        final r = await _dio.post<dynamic>('/grns/$id/post');
        return GrnView.fromJson(jsonMap(r.data));
      });

  // --- debit notes ----------------------------------------------------------

  /// GET /debit-notes
  Future<List<DebitNoteView>> debitNotes({String? status}) => _guard(() async {
        final r = await _dio.get<dynamic>('/debit-notes', queryParameters: {
          if (status != null) 'status': status,
        });
        return [for (final d in jsonMaps(r.data)) DebitNoteView.fromJson(d)];
      });

  /// POST /debit-notes/:id/settle
  Future<DebitNoteView> settleDebitNote(String id) => _guard(() async {
        final r = await _dio.post<dynamic>('/debit-notes/$id/settle');
        return DebitNoteView.fromJson(jsonMap(r.data));
      });
}

final procurementVendorsProvider = FutureProvider<List<VendorView>>(
  (ref) => ref.watch(procurementRepositoryProvider).vendors(),
);

/// Purchase orders for a status filter (null means all).
final purchaseOrdersProvider = FutureProvider.family<PoListPage, String?>(
  (ref, status) => ref.watch(procurementRepositoryProvider).purchaseOrders(status: status),
);

final goodsReceivedProvider = FutureProvider<List<GrnSummary>>(
  (ref) => ref.watch(procurementRepositoryProvider).grns(),
);

final debitNotesProvider = FutureProvider<List<DebitNoteView>>(
  (ref) => ref.watch(procurementRepositoryProvider).debitNotes(),
);

final reorderSuggestionsProvider = FutureProvider.family<List<ReorderSuggestion>, String?>(
  (ref, locationId) =>
      ref.watch(procurementRepositoryProvider).reorderSuggestions(locationId: locationId),
);
