import 'dart:typed_data';

import 'guest_models.dart';
import 'guest_requests_repository.dart';

/// In-memory staff guest API with the design board's data (R4 Deepa, T7
/// Karthik claimed by Ravi, R2 bill, B5 call waiter). Used by
/// `--dart-define=GUEST_MOCK=true` and by widget tests. Records the last
/// confirm/reject so tests can check what was sent.
class MockGuestRequestsRepository implements GuestRequestsRepository {
  MockGuestRequestsRepository({
    this.currentUserId = 'me',
    this.currentUserName = 'You',
    DateTime? now,
    List<GuestRequest>? requests,
    List<ServiceRequest>? serviceRequests,
    GuestConfig? config,
    Map<String, String>? pins,
  }) {
    final at = now ?? DateTime.now();
    _requests = requests ?? demoRequests(at);
    _service = serviceRequests ?? demoServiceRequests(at);
    _config = config ?? const GuestConfig();
    _pins = pins ?? {'t-b2': '4817'};
  }

  final String currentUserId;
  final String currentUserName;

  late List<GuestRequest> _requests;
  late List<ServiceRequest> _service;
  late GuestConfig _config;
  late Map<String, String> _pins;

  /// Last confirm: request id and items (null = as placed).
  ({String id, List<GuestLine>? items})? lastConfirm;
  ({String id, String reason})? lastReject;
  String? lastNewStaticOtp;
  final List<String> rotated = [];
  final List<String> acked = [];

  static List<GuestRequest> demoRequests(DateTime now) => [
        GuestRequest(
          id: 'gr-r4',
          tableId: 't-r4',
          tableName: 'R4',
          guestName: 'Deepa',
          phoneMasked: '+91 98•••••210',
          roundNo: 2,
          createdAt: now.subtract(const Duration(minutes: 1)),
          lines: const [
            GuestLine(
              productId: 'p-mojito',
              name: 'Classic Mojito',
              modifiers: [GuestModifier(groupId: 'g-ice', optionId: 'o-rocks', name: 'On the rocks')],
              quantity: 2,
              unitPrice: 245,
              isAlcohol: true,
            ),
            GuestLine(
              productId: 'p-colada',
              name: 'Virgin Colada',
              quantity: 1,
              unitPrice: 220,
              note: 'less sugar',
            ),
          ],
        ),
        GuestRequest(
          id: 'gr-t7',
          tableId: 't-t7',
          tableName: 'T7',
          guestName: 'Karthik',
          phoneMasked: '+91 90•••••118',
          createdAt: now.subtract(const Duration(minutes: 4)),
          claimedById: 'u-ravi',
          claimedByName: 'Ravi',
          lines: const [
            GuestLine(
              productId: 'p-whisky',
              name: 'House Whisky 60 ml',
              quantity: 4,
              unitPrice: 340,
              isAlcohol: true,
            ),
          ],
        ),
      ];

  static List<ServiceRequest> demoServiceRequests(DateTime now) => [
        ServiceRequest(
          id: 'sr-r2',
          tableId: 't-r2',
          tableName: 'R2',
          type: ServiceRequestTypes.bill,
          createdAt: now.subtract(const Duration(minutes: 2)),
        ),
        ServiceRequest(
          id: 'sr-b5',
          tableId: 't-b5',
          tableName: 'B5',
          type: ServiceRequestTypes.callWaiter,
          createdAt: now.subtract(const Duration(minutes: 1)),
        ),
      ];

  @override
  Future<List<GuestRequest>> pendingRequests() async =>
      [for (final r in _requests) if (r.isPending) r];

  @override
  Future<GuestRequest> claim(String id) async {
    final i = _requests.indexWhere((r) => r.id == id);
    final claimed = _requests[i].copyWith(claimedById: currentUserId, claimedByName: currentUserName);
    _requests[i] = claimed;
    return claimed;
  }

  void _decide(String id, String status) {
    final i = _requests.indexWhere((r) => r.id == id);
    if (i >= 0) _requests[i] = _requests[i].copyWith(status: status);
  }

  @override
  Future<void> confirm(String id, {List<GuestLine>? items}) async {
    lastConfirm = (id: id, items: items);
    _decide(id, GuestRequestStatuses.confirmed);
  }

  @override
  Future<void> reject(String id, {required String reason}) async {
    lastReject = (id: id, reason: reason);
    _decide(id, GuestRequestStatuses.rejected);
  }

  @override
  Future<List<ServiceRequest>> openServiceRequests() async => List.of(_service);

  @override
  Future<ServiceRequest> acknowledge(String id) async {
    acked.add(id);
    final i = _service.indexWhere((s) => s.id == id);
    _service[i] = _service[i].copyWith(status: ServiceRequestStatuses.acknowledged);
    return _service[i];
  }

  @override
  Future<void> done(String id) async => _service.removeWhere((s) => s.id == id);

  @override
  Future<GuestConfig> config() async => _config;

  @override
  Future<GuestConfig> saveConfig(GuestConfig config, {String? newStaticOtp}) async {
    lastNewStaticOtp = newStaticOtp;
    _config = config.copyWith(hasStaticOtp: config.hasStaticOtp || newStaticOtp != null);
    return _config;
  }

  @override
  Future<String?> guestPin(String tableId) async => _pins[tableId];

  @override
  Future<void> rotateQr(String tableId) async => rotated.add(tableId);

  /// A minimal valid one-page PDF.
  @override
  Future<Uint8List> qrSheet({String? areaId}) async => Uint8List.fromList(
        '%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[]/Count 0>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF'
            .codeUnits,
      );
}
