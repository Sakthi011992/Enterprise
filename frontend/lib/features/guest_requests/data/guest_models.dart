/// Staff-side guest ordering models (PLAN 2.1, 2.6, 2.7). Parsing is
/// defensive: the staff API response shapes are not frozen in the plan, so
/// each field accepts the obvious alternative key.
library;

import 'package:intl/intl.dart';

import '../../pos/data/pos_models.dart';

/// Wire values for `GuestRequestStatus`.
abstract final class GuestRequestStatuses {
  static const pending = 'PENDING';
  static const confirmed = 'CONFIRMED';
  static const rejected = 'REJECTED';
  static const cancelled = 'CANCELLED';
  static const expired = 'EXPIRED';
}

/// Wire values for `ServiceRequestType` and `ServiceRequestStatus`.
abstract final class ServiceRequestTypes {
  static const callWaiter = 'CALL_WAITER';
  static const bill = 'BILL';

  static String label(String type) => type == bill ? 'Bill please' : 'Call waiter';
}

abstract final class ServiceRequestStatuses {
  static const open = 'OPEN';
  static const acknowledged = 'ACKNOWLEDGED';
  static const done = 'DONE';
}

/// Wire values for routing, verification and checkout in `GuestConfig`.
abstract final class GuestRouting {
  static const direct = 'DIRECT';
  static const waiter = 'WAITER';
}

abstract final class GuestVerifyMethods {
  static const staticOtp = 'STATIC_OTP';
  static const tablePin = 'TABLE_PIN';
  static const smsOtp = 'SMS_OTP';
}

abstract final class GuestCheckoutModes {
  static const waiter = 'WAITER';
  static const online = 'ONLINE';
}

double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

String? _str(Map<String, dynamic> j, List<String> keys) {
  for (final k in keys) {
    final v = j[k];
    if (v != null && '$v'.isNotEmpty) return '$v';
  }
  return null;
}

final _inr = NumberFormat.decimalPattern('en_IN');

/// "₹1,360" (no paise when whole), "₹245.50" otherwise.
String formatInr(num value) {
  final whole = value == value.roundToDouble();
  return whole
      ? '₹${_inr.format(value.round())}'
      : '₹${NumberFormat('#,##,##0.00', 'en_IN').format(value)}';
}

/// "+91 98•••••210" from an E.164 or already-masked number.
String maskPhone(String phone) {
  if (phone.contains('•')) return phone;
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 10) return phone;
  final local = digits.substring(digits.length - 10);
  return '+91 ${local.substring(0, 2)}•••••${local.substring(7)}';
}

/// "1 min", "12 min", "1 h 5 min". Under a minute reads "now".
String ageText(Duration d) {
  final m = d.isNegative ? 0 : d.inMinutes;
  if (m < 1) return 'now';
  if (m < 60) return '$m min';
  return '${m ~/ 60} h ${m % 60} min';
}

/// A modifier choice on a guest line: wire refs plus the display name.
class GuestModifier {
  const GuestModifier({required this.groupId, required this.optionId, required this.name});

  final String groupId;
  final String optionId;
  final String name;

  factory GuestModifier.fromJson(Object? raw) {
    if (raw is String) return GuestModifier(groupId: '', optionId: '', name: raw);
    final j = asMap(raw);
    return GuestModifier(
      groupId: readString(j, 'groupId'),
      optionId: readString(j, 'optionId'),
      name: _str(j, ['name', 'optionName', 'label']) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'groupId': groupId, 'optionId': optionId};
}

/// One line of a guest round.
class GuestLine {
  const GuestLine({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    this.variantId,
    this.variantName,
    this.modifiers = const [],
    this.note,
    this.isAlcohol = false,
  });

  final String productId;
  final String? variantId;
  final String name;
  final String? variantName;
  final List<GuestModifier> modifiers;
  final int quantity;

  /// Price of one unit including modifiers.
  final double unitPrice;
  final String? note;
  final bool isAlcohol;

  double get lineTotal => unitPrice * quantity;

  /// "Classic Mojito · On the rocks".
  String get title {
    final parts = [
      variantName == null || variantName!.isEmpty ? name : '$name $variantName',
      ...modifiers.map((m) => m.name).where((n) => n.isNotEmpty),
    ];
    return parts.join(' · ');
  }

  GuestLine copyWith({int? quantity}) => GuestLine(
        productId: productId,
        variantId: variantId,
        name: name,
        variantName: variantName,
        modifiers: modifiers,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice,
        note: note,
        isAlcohol: isAlcohol,
      );

  factory GuestLine.fromJson(Map<String, dynamic> j) {
    final qty = readInt(j, 'quantity', readInt(j, 'qty', 1));
    final unit = j['unitPrice'] != null
        ? _num(j['unitPrice'])
        : (qty == 0 ? 0.0 : _num(j['lineTotal']) / qty);
    return GuestLine(
      productId: readString(j, 'productId'),
      variantId: readStringOrNull(j, 'variantId'),
      name: _str(j, ['name', 'productName']) ?? '',
      variantName: _str(j, ['variantName', 'variant']),
      modifiers: [for (final m in (j['modifiers'] as List?) ?? const []) GuestModifier.fromJson(m)],
      quantity: qty,
      unitPrice: unit,
      note: readStringOrNull(j, 'note'),
      isAlcohol: readBool(j, 'isAlcohol'),
    );
  }

  /// Body item for `POST /guest-requests/:id/confirm` (same shape as submitted).
  Map<String, dynamic> toConfirmJson() => {
        'productId': productId,
        if (variantId != null) 'variantId': variantId,
        'quantity': quantity,
        'modifiers': [
          for (final m in modifiers)
            if (m.optionId.isNotEmpty) m.toJson()
        ],
        if (note != null && note!.isNotEmpty) 'note': note,
      };
}

/// One placed guest round waiting for (or decided by) a waiter.
class GuestRequest {
  const GuestRequest({
    required this.id,
    required this.tableId,
    required this.tableName,
    required this.guestName,
    required this.phoneMasked,
    required this.lines,
    required this.createdAt,
    this.status = GuestRequestStatuses.pending,
    this.claimedById,
    this.claimedByName,
    this.roundNo,
    double? total,
  }) : _total = total;

  final String id;
  final String tableId;
  final String tableName;
  final String guestName;
  final String phoneMasked;
  final List<GuestLine> lines;
  final DateTime createdAt;
  final String status;
  final String? claimedById;
  final String? claimedByName;
  final int? roundNo;
  final double? _total;

  double get total => _total ?? lines.fold(0.0, (s, l) => s + l.lineTotal);
  bool get hasAlcohol => lines.any((l) => l.isAlcohol);
  bool get isPending => status == GuestRequestStatuses.pending;

  GuestRequest copyWith({String? status, String? claimedById, String? claimedByName}) =>
      GuestRequest(
        id: id,
        tableId: tableId,
        tableName: tableName,
        guestName: guestName,
        phoneMasked: phoneMasked,
        lines: lines,
        createdAt: createdAt,
        status: status ?? this.status,
        claimedById: claimedById ?? this.claimedById,
        claimedByName: claimedByName ?? this.claimedByName,
        roundNo: roundNo,
        total: _total,
      );

  factory GuestRequest.fromJson(Map<String, dynamic> j) {
    final table = j['table'];
    final participant = j['participant'] ?? j['guest'];
    final p = participant is Map ? asMap(participant) : const <String, dynamic>{};
    final claimedBy = j['claimedBy'];
    final c = claimedBy is Map ? asMap(claimedBy) : const <String, dynamic>{};
    return GuestRequest(
      id: readString(j, 'id', readString(j, 'requestId')),
      tableId: readString(j, 'tableId', table is Map ? readString(asMap(table), 'id') : ''),
      tableName: table is Map
          ? readString(asMap(table), 'name')
          : (_str(j, ['tableName', 'table']) ?? ''),
      guestName: _str(j, ['by', 'guestName', 'name']) ?? _str(p, ['name']) ?? 'Guest',
      phoneMasked: maskPhone(_str(j, ['phoneMasked', 'phone']) ?? _str(p, ['phoneMasked', 'phone']) ?? ''),
      lines: [for (final l in asMaps(j['lines'] ?? j['items'])) GuestLine.fromJson(l)],
      createdAt: readDate(j, 'createdAt') ?? DateTime.now(),
      status: readString(j, 'status', GuestRequestStatuses.pending),
      claimedById: readStringOrNull(j, 'claimedById') ?? _str(c, ['id']),
      claimedByName: readStringOrNull(j, 'claimedByName') ?? _str(c, ['displayName', 'name']),
      roundNo: readIntOrNull(j, 'roundNo') ?? readIntOrNull(j, 'round'),
      total: j['total'] == null ? null : _num(j['total']),
    );
  }
}

/// "Bill please" or "Call waiter" from a table.
class ServiceRequest {
  const ServiceRequest({
    required this.id,
    required this.tableId,
    required this.tableName,
    required this.type,
    required this.createdAt,
    this.status = ServiceRequestStatuses.open,
  });

  final String id;
  final String tableId;
  final String tableName;
  final String type;
  final String status;
  final DateTime createdAt;

  bool get isBill => type == ServiceRequestTypes.bill;
  bool get isAcknowledged => status == ServiceRequestStatuses.acknowledged;

  ServiceRequest copyWith({String? status}) => ServiceRequest(
        id: id,
        tableId: tableId,
        tableName: tableName,
        type: type,
        createdAt: createdAt,
        status: status ?? this.status,
      );

  factory ServiceRequest.fromJson(Map<String, dynamic> j) {
    final table = j['table'];
    return ServiceRequest(
      id: readString(j, 'id'),
      tableId: readString(j, 'tableId', table is Map ? readString(asMap(table), 'id') : ''),
      tableName: table is Map
          ? readString(asMap(table), 'name')
          : (_str(j, ['tableName', 'table']) ?? ''),
      type: readString(j, 'type', ServiceRequestTypes.callWaiter),
      status: readString(j, 'status', ServiceRequestStatuses.open),
      createdAt: readDate(j, 'createdAt') ?? DateTime.now(),
    );
  }
}

/// App-level guest configuration (PLAN 2.1). The static OTP is never read
/// back; [hasStaticOtp] says whether one is set.
class GuestConfig {
  const GuestConfig({
    this.enabled = true,
    this.routing = GuestRouting.waiter,
    this.method = GuestVerifyMethods.staticOtp,
    this.codeLength = 6,
    this.hasStaticOtp = true,
    this.ageGate = true,
    this.minAge = 25,
    this.requireSeated = true,
    this.requestTtlMinutes = 10,
    this.maxQtyPerLine = 10,
    this.maxLinesPerRound = 20,
    this.allowGuestCancel = true,
    this.checkout = GuestCheckoutModes.waiter,
  });

  final bool enabled;
  final String routing;
  final String method;
  final int codeLength;
  final bool hasStaticOtp;
  final bool ageGate;
  final int minAge;
  final bool requireSeated;
  final int requestTtlMinutes;
  final int maxQtyPerLine;
  final int maxLinesPerRound;
  final bool allowGuestCancel;
  final String checkout;

  GuestConfig copyWith({
    bool? enabled,
    String? routing,
    String? method,
    bool? hasStaticOtp,
    bool? ageGate,
    int? minAge,
    bool? requireSeated,
    int? requestTtlMinutes,
    bool? allowGuestCancel,
  }) =>
      GuestConfig(
        enabled: enabled ?? this.enabled,
        routing: routing ?? this.routing,
        method: method ?? this.method,
        codeLength: codeLength,
        hasStaticOtp: hasStaticOtp ?? this.hasStaticOtp,
        ageGate: ageGate ?? this.ageGate,
        minAge: minAge ?? this.minAge,
        requireSeated: requireSeated ?? this.requireSeated,
        requestTtlMinutes: requestTtlMinutes ?? this.requestTtlMinutes,
        maxQtyPerLine: maxQtyPerLine,
        maxLinesPerRound: maxLinesPerRound,
        allowGuestCancel: allowGuestCancel ?? this.allowGuestCancel,
        checkout: checkout,
      );

  factory GuestConfig.fromJson(Map<String, dynamic> raw) {
    final j = raw['config'] is Map ? asMap(raw['config']) : raw;
    final v = asMap(j['verification']);
    return GuestConfig(
      enabled: readBool(j, 'enabled', true),
      routing: readString(j, 'routing', GuestRouting.waiter),
      method: readString(v, 'method', GuestVerifyMethods.staticOtp),
      codeLength: readInt(v, 'codeLength', 6),
      hasStaticOtp: readBool(v, 'hasStaticOtp', readBool(v, 'staticOtpSet', true)),
      ageGate: readBool(j, 'ageGate', true),
      minAge: readInt(j, 'minAge', 25),
      requireSeated: readBool(j, 'requireSeated', true),
      requestTtlMinutes: readInt(j, 'requestTtlMinutes', 10),
      maxQtyPerLine: readInt(j, 'maxQtyPerLine', 10),
      maxLinesPerRound: readInt(j, 'maxLinesPerRound', 20),
      allowGuestCancel: readBool(j, 'allowGuestCancel', true),
      checkout: readString(j, 'checkout', GuestCheckoutModes.waiter),
    );
  }

  /// Body for `PUT /settings/guest`. [newStaticOtp] only when the admin set one.
  Map<String, dynamic> toJson({String? newStaticOtp}) => {
        'enabled': enabled,
        'routing': routing,
        'verification': {
          'method': method,
          'codeLength': codeLength,
          if (newStaticOtp != null) 'newStaticOtp': newStaticOtp,
        },
        'ageGate': ageGate,
        'minAge': minAge,
        'requireSeated': requireSeated,
        'requestTtlMinutes': requestTtlMinutes,
        'maxQtyPerLine': maxQtyPerLine,
        'maxLinesPerRound': maxLinesPerRound,
        'allowGuestCancel': allowGuestCancel,
        'checkout': checkout,
      };
}
