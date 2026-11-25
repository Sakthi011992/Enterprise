/// Procurement data models (PLAN 1.7, "Procurement" section). Money is a string
/// with 2 dp; quantities are purchase units with 3 dp.
library;

import '../../inventory/data/json_read.dart';

/// Wire values of `PurchaseOrderStatus`.
abstract final class PoStatus {
  static const draft = 'DRAFT';
  static const pendingApproval = 'PENDING_APPROVAL';
  static const approved = 'APPROVED';
  static const sent = 'SENT';
  static const partlyReceived = 'PARTLY_RECEIVED';
  static const received = 'RECEIVED';
  static const invoiceMismatch = 'INVOICE_MISMATCH';
  static const cancelled = 'CANCELLED';

  static const order = [
    draft,
    pendingApproval,
    approved,
    sent,
    partlyReceived,
    invoiceMismatch,
    received,
    cancelled,
  ];

  static String label(String status) => switch (status) {
        PoStatus.draft => 'Draft',
        PoStatus.pendingApproval => 'Waiting approval',
        PoStatus.approved => 'Approved',
        PoStatus.sent => 'Sent to vendor',
        PoStatus.partlyReceived => 'Partly received',
        PoStatus.invoiceMismatch => 'Invoice mismatch',
        PoStatus.received => 'Received',
        PoStatus.cancelled => 'Cancelled',
        _ => status.toLowerCase(),
      };
}

/// Wire values of `GrnStatus` and `DebitNoteStatus`.
abstract final class GrnStatuses {
  static const draft = 'DRAFT';
  static const posted = 'POSTED';
}

abstract final class DebitNoteStatuses {
  static const open = 'OPEN';
  static const settled = 'SETTLED';
  static const cancelled = 'CANCELLED';
}

// --- vendors ----------------------------------------------------------------

class VendorView {
  const VendorView({
    required this.id,
    required this.name,
    this.contactName,
    this.phone,
    this.email,
    this.gstin,
    this.address,
    this.paymentTermsDays = 30,
    this.isActive = true,
    this.openPoCount = 0,
  });

  final String id;
  final String name;
  final String? contactName;
  final String? phone;
  final String? email;
  final String? gstin;
  final String? address;
  final int paymentTermsDays;
  final bool isActive;
  final int openPoCount;

  factory VendorView.fromJson(Map<String, dynamic> j) => VendorView(
        id: jsonStr(j, 'id'),
        name: jsonStr(j, 'name'),
        contactName: jsonStrOrNull(j, 'contactName'),
        phone: jsonStrOrNull(j, 'phone'),
        email: jsonStrOrNull(j, 'email'),
        gstin: jsonStrOrNull(j, 'gstin'),
        address: jsonStrOrNull(j, 'address'),
        paymentTermsDays: jsonInt(j, 'paymentTermsDays', 30),
        isActive: jsonBool(j, 'isActive', true),
        openPoCount: jsonInt(j, 'openPoCount'),
      );

  /// Body for POST and PUT /vendors.
  Map<String, dynamic> toJson() => {
        'name': name,
        'contactName': contactName,
        'phone': phone,
        'email': email,
        'gstin': gstin,
        'address': address,
        'paymentTermsDays': paymentTermsDays,
        'isActive': isActive,
      };
}

// --- purchase orders --------------------------------------------------------

class PoSummary {
  const PoSummary({
    required this.id,
    required this.number,
    this.vendor,
    this.location,
    required this.total,
    this.dueDate,
    required this.status,
    this.createdAt,
  });

  final String id;
  final String number;
  final RefName? vendor;
  final RefName? location;
  final String total;
  final DateTime? dueDate;
  final String status;
  final DateTime? createdAt;

  factory PoSummary.fromJson(Map<String, dynamic> j) => PoSummary(
        id: jsonStr(j, 'id'),
        number: jsonStr(j, 'number'),
        vendor: RefName.maybe(j['vendor']),
        location: RefName.maybe(j['location']),
        total: jsonDecimal(j, 'total', '0.00'),
        dueDate: jsonDate(j, 'dueDate'),
        status: jsonStr(j, 'status', PoStatus.draft),
        createdAt: jsonDate(j, 'createdAt'),
      );
}

/// `GET /purchase-orders` response: status counts plus the rows.
class PoListPage {
  const PoListPage({this.counts = const {}, this.items = const []});

  final Map<String, int> counts;
  final List<PoSummary> items;

  factory PoListPage.fromJson(Map<String, dynamic> j) {
    final rawCounts = jsonMap(j['counts']);
    return PoListPage(
      counts: {
        for (final e in rawCounts.entries) e.key: jsonInt(rawCounts, e.key),
      },
      items: [for (final p in jsonMaps(j['items'])) PoSummary.fromJson(p)],
    );
  }
}

class PoLine {
  const PoLine({
    required this.id,
    required this.stockItemId,
    required this.name,
    required this.purchaseUnitName,
    required this.qty,
    required this.rate,
    required this.total,
    required this.receivedQty,
  });

  final String id;
  final String stockItemId;
  final String name;
  final String purchaseUnitName;

  /// Purchase units, 3 dp.
  final String qty;

  /// ₹ per purchase unit, 2 dp.
  final String rate;
  final String total;
  final String receivedQty;

  factory PoLine.fromJson(Map<String, dynamic> j) => PoLine(
        id: jsonStr(j, 'id'),
        stockItemId: jsonStr(j, 'stockItemId'),
        name: jsonStr(j, 'name'),
        purchaseUnitName: jsonStr(j, 'purchaseUnitName', 'Unit'),
        qty: jsonDecimal(j, 'qty', '0.000'),
        rate: jsonDecimal(j, 'rate', '0.00'),
        total: jsonDecimal(j, 'total', '0.00'),
        receivedQty: jsonDecimal(j, 'receivedQty', '0.000'),
      );
}

class PoView {
  const PoView({
    required this.summary,
    this.transportPermitNo,
    this.note,
    this.createdBy,
    this.approvedBy,
    this.approvedAt,
    this.sentAt,
    this.lines = const [],
    this.grns = const [],
  });

  final PoSummary summary;
  final String? transportPermitNo;
  final String? note;
  final RefName? createdBy;
  final RefName? approvedBy;
  final DateTime? approvedAt;
  final DateTime? sentAt;
  final List<PoLine> lines;
  final List<GrnSummary> grns;

  String get id => summary.id;
  String get status => summary.status;

  factory PoView.fromJson(Map<String, dynamic> j) => PoView(
        summary: PoSummary.fromJson(j),
        transportPermitNo: jsonStrOrNull(j, 'transportPermitNo'),
        note: jsonStrOrNull(j, 'note'),
        createdBy: RefName.maybe(j['createdBy']),
        approvedBy: RefName.maybe(j['approvedBy']),
        approvedAt: jsonDate(j, 'approvedAt'),
        sentAt: jsonDate(j, 'sentAt'),
        lines: [for (final l in jsonMaps(j['lines'])) PoLine.fromJson(l)],
        grns: [for (final g in jsonMaps(j['grns'])) GrnSummary.fromJson(g)],
      );
}

// --- reorder ----------------------------------------------------------------

class ReorderSuggestion {
  const ReorderSuggestion({
    required this.stockItemId,
    required this.name,
    required this.locationId,
    required this.locationName,
    required this.onHandDisplay,
    required this.parDisplay,
    required this.suggestedQty,
    required this.purchaseUnitName,
    this.vendor,
    required this.rate,
  });

  final String stockItemId;
  final String name;
  final String locationId;
  final String locationName;
  final String onHandDisplay;
  final String parDisplay;

  /// Purchase units, at least 1.
  final int suggestedQty;
  final String purchaseUnitName;
  final RefName? vendor;

  /// ₹ per purchase unit (last purchase rate, or 0).
  final num rate;

  factory ReorderSuggestion.fromJson(Map<String, dynamic> j) => ReorderSuggestion(
        stockItemId: jsonStr(j, 'stockItemId'),
        name: jsonStr(j, 'name'),
        locationId: jsonStr(j, 'locationId'),
        locationName: jsonStr(j, 'locationName'),
        onHandDisplay: jsonStr(j, 'onHandDisplay'),
        parDisplay: jsonStr(j, 'parDisplay'),
        suggestedQty: jsonInt(j, 'suggestedQty', 1),
        purchaseUnitName: jsonStr(j, 'purchaseUnitName', 'Unit'),
        vendor: RefName.maybe(j['vendor']),
        rate: decimalValue(j['rate']),
      );
}

// --- goods received ---------------------------------------------------------

class GrnSummary {
  const GrnSummary({
    required this.id,
    required this.number,
    this.poNumber,
    this.vendor,
    this.location,
    required this.status,
    this.receivedOn,
    required this.invoiceValue,
    required this.payable,
    this.mismatch = false,
  });

  final String id;
  final String number;
  final String? poNumber;
  final RefName? vendor;
  final RefName? location;
  final String status;
  final DateTime? receivedOn;
  final String invoiceValue;
  final String payable;
  final bool mismatch;

  factory GrnSummary.fromJson(Map<String, dynamic> j) => GrnSummary(
        id: jsonStr(j, 'id'),
        number: jsonStr(j, 'number'),
        poNumber: jsonStrOrNull(j, 'poNumber'),
        vendor: RefName.maybe(j['vendor']),
        location: RefName.maybe(j['location']),
        status: jsonStr(j, 'status', GrnStatuses.draft),
        receivedOn: jsonDate(j, 'receivedOn'),
        invoiceValue: jsonDecimal(j, 'invoiceValue', '0.00'),
        payable: jsonDecimal(j, 'payable', '0.00'),
        mismatch: jsonBool(j, 'mismatch'),
      );
}

/// One line of a GRN. Quantities are purchase units (3 dp), `rate` is the
/// invoice rate per purchase unit.
class GrnLine {
  const GrnLine({
    this.id,
    this.poLineId,
    required this.stockItemId,
    required this.name,
    required this.purchaseUnitName,
    required this.orderedQty,
    required this.invoicedQty,
    required this.receivedQty,
    required this.damagedQty,
    required this.rate,
    this.batch,
    this.expiry,
    this.status = 'OK',
  });

  final String? id;
  final String? poLineId;
  final String stockItemId;
  final String name;
  final String purchaseUnitName;
  final num orderedQty;
  final num invoicedQty;
  final num receivedQty;
  final num damagedQty;
  final num rate;
  final String? batch;

  /// yyyy-MM-dd
  final String? expiry;

  /// OK | SHORT | OVER_INVOICED | DAMAGED, as the server computes it.
  final String status;

  factory GrnLine.fromJson(Map<String, dynamic> j) => GrnLine(
        id: jsonStrOrNull(j, 'id'),
        poLineId: jsonStrOrNull(j, 'poLineId'),
        stockItemId: jsonStr(j, 'stockItemId'),
        name: jsonStr(j, 'name'),
        purchaseUnitName: jsonStr(j, 'purchaseUnitName', 'Unit'),
        orderedQty: decimalValue(j['orderedQty']),
        invoicedQty: decimalValue(j['invoicedQty']),
        receivedQty: decimalValue(j['receivedQty']),
        damagedQty: decimalValue(j['damagedQty']),
        rate: decimalValue(j['rate']),
        batch: jsonStrOrNull(j, 'batch'),
        expiry: jsonStrOrNull(j, 'expiry'),
        status: jsonStr(j, 'status', 'OK'),
      );

  /// Body line for POST and PUT /grns.
  Map<String, dynamic> toJson() => {
        if (poLineId != null) 'poLineId': poLineId,
        'stockItemId': stockItemId,
        'orderedQty': orderedQty,
        'invoicedQty': invoicedQty,
        'receivedQty': receivedQty,
        'damagedQty': damagedQty,
        'rate': rate,
        'batch': batch,
        'expiry': expiry,
      };

  GrnLine copyWith({
    num? orderedQty,
    num? invoicedQty,
    num? receivedQty,
    num? damagedQty,
    num? rate,
    String? batch,
    String? expiry,
  }) =>
      GrnLine(
        id: id,
        poLineId: poLineId,
        stockItemId: stockItemId,
        name: name,
        purchaseUnitName: purchaseUnitName,
        orderedQty: orderedQty ?? this.orderedQty,
        invoicedQty: invoicedQty ?? this.invoicedQty,
        receivedQty: receivedQty ?? this.receivedQty,
        damagedQty: damagedQty ?? this.damagedQty,
        rate: rate ?? this.rate,
        batch: batch ?? this.batch,
        expiry: expiry ?? this.expiry,
        status: status,
      );
}

class GrnPreviewStock {
  const GrnPreviewStock({required this.name, required this.qty, required this.display});

  final String name;
  final String qty;
  final String display;

  factory GrnPreviewStock.fromJson(Map<String, dynamic> j) => GrnPreviewStock(
        name: jsonStr(j, 'name'),
        qty: jsonDecimal(j, 'qty', '0.000'),
        display: jsonStr(j, 'display'),
      );
}

/// Server-side preview of what posting will do (also computed for drafts).
class GrnPreview {
  const GrnPreview({
    this.stockAdded = const [],
    this.debitNote = '0.00',
    this.wastage = '0.00',
    this.payable = '0.00',
  });

  final List<GrnPreviewStock> stockAdded;
  final String debitNote;
  final String wastage;
  final String payable;

  factory GrnPreview.fromJson(Map<String, dynamic> j) => GrnPreview(
        stockAdded: [for (final s in jsonMaps(j['stockAdded'])) GrnPreviewStock.fromJson(s)],
        debitNote: jsonDecimal(j, 'debitNote', '0.00'),
        wastage: jsonDecimal(j, 'wastage', '0.00'),
        payable: jsonDecimal(j, 'payable', '0.00'),
      );
}

class GrnView {
  const GrnView({
    required this.summary,
    this.poId,
    this.vendorInvoiceNo,
    this.invoiceDate,
    this.transportPermitNo,
    this.invoicePhotoUrl,
    this.poValue = '0.00',
    this.receivedValue = '0.00',
    this.debitNoteAmount = '0.00',
    this.damagedValue = '0.00',
    this.lines = const [],
    this.preview,
  });

  final GrnSummary summary;
  final String? poId;
  final String? vendorInvoiceNo;
  final DateTime? invoiceDate;
  final String? transportPermitNo;
  final String? invoicePhotoUrl;
  final String poValue;
  final String receivedValue;
  final String debitNoteAmount;
  final String damagedValue;
  final List<GrnLine> lines;
  final GrnPreview? preview;

  String get id => summary.id;
  String get status => summary.status;

  factory GrnView.fromJson(Map<String, dynamic> j) {
    final preview = j['preview'];
    return GrnView(
      summary: GrnSummary.fromJson(j),
      poId: jsonStrOrNull(j, 'poId'),
      vendorInvoiceNo: jsonStrOrNull(j, 'vendorInvoiceNo'),
      invoiceDate: jsonDate(j, 'invoiceDate'),
      transportPermitNo: jsonStrOrNull(j, 'transportPermitNo'),
      invoicePhotoUrl: jsonStrOrNull(j, 'invoicePhotoUrl'),
      poValue: jsonDecimal(j, 'poValue', '0.00'),
      receivedValue: jsonDecimal(j, 'receivedValue', '0.00'),
      debitNoteAmount: jsonDecimal(j, 'debitNoteAmount', '0.00'),
      damagedValue: jsonDecimal(j, 'damagedValue', '0.00'),
      lines: [for (final l in jsonMaps(j['lines'])) GrnLine.fromJson(l)],
      preview: preview is Map ? GrnPreview.fromJson(jsonMap(preview)) : null,
    );
  }
}

// --- debit notes ------------------------------------------------------------

class DebitNoteView {
  const DebitNoteView({
    required this.id,
    required this.number,
    this.vendor,
    this.grnNumber,
    required this.amount,
    required this.reason,
    required this.status,
    this.createdAt,
  });

  final String id;
  final String number;
  final RefName? vendor;
  final String? grnNumber;
  final String amount;
  final String reason;
  final String status;
  final DateTime? createdAt;

  factory DebitNoteView.fromJson(Map<String, dynamic> j) => DebitNoteView(
        id: jsonStr(j, 'id'),
        number: jsonStr(j, 'number'),
        vendor: RefName.maybe(j['vendor']),
        grnNumber: jsonStrOrNull(j, 'grnNumber'),
        amount: jsonDecimal(j, 'amount', '0.00'),
        reason: jsonStr(j, 'reason'),
        status: jsonStr(j, 'status', DebitNoteStatuses.open),
        createdAt: jsonDate(j, 'createdAt'),
      );
}
