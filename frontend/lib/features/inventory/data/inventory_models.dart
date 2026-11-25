/// Inventory data models (PLAN 1.7, "Inventory" section). Field names are the
/// JSON keys. Quantities are strings with 3 dp; `...Display` strings are shown
/// as they come from the server.
library;

import 'json_read.dart';
import 'stock_format.dart';

/// Status values of `StockItemRow.status`.
abstract final class StockStatus {
  static const ok = 'OK';
  static const belowPar = 'BELOW_PAR';
  static const variance = 'VARIANCE';
  static const expires = 'EXPIRES';
  static const negative = 'NEGATIVE';
}

/// Wire values for `StockItemInput.baseUnit` and `StockCountStatus`.
abstract final class BaseUnits {
  static const ml = 'ML';
  static const g = 'G';
  static const pc = 'PC';
}

// --- summary ----------------------------------------------------------------

class InventorySummary {
  const InventorySummary({
    required this.stockValue,
    required this.pourPercent,
    required this.pourCost,
    required this.pourRevenue,
    required this.liquorVarianceQty,
    required this.liquorVarianceValue,
    required this.belowParCount,
  });

  final String stockValue;
  final String pourPercent;
  final String pourCost;
  final String pourRevenue;
  final String liquorVarianceQty;
  final String liquorVarianceValue;
  final int belowParCount;

  factory InventorySummary.fromJson(Map<String, dynamic> j) {
    final pour = jsonMap(j['pourCost7d']);
    final variance = jsonMap(j['liquorVariance7d']);
    return InventorySummary(
      stockValue: jsonDecimal(j, 'stockValue'),
      pourPercent: jsonDecimal(pour, 'percent', '0.0'),
      pourCost: jsonDecimal(pour, 'cost', '0.00'),
      pourRevenue: jsonDecimal(pour, 'revenue', '0.00'),
      liquorVarianceQty: jsonDecimal(variance, 'qty', '0.000'),
      liquorVarianceValue: jsonDecimal(variance, 'value', '0.00'),
      belowParCount: jsonInt(j, 'belowParCount'),
    );
  }
}

// --- locations --------------------------------------------------------------

class LocationView {
  const LocationView({
    required this.id,
    required this.name,
    required this.kind,
    this.stations = const [],
    this.isDefaultSales = false,
    this.itemCount = 0,
    this.value = '0.00',
  });

  final String id;
  final String name;

  /// STORE | BAR | KITCHEN | CELLAR
  final String kind;
  final List<String> stations;
  final bool isDefaultSales;
  final int itemCount;
  final String value;

  factory LocationView.fromJson(Map<String, dynamic> j) => LocationView(
        id: jsonStr(j, 'id'),
        name: jsonStr(j, 'name'),
        kind: jsonStr(j, 'kind', 'STORE'),
        stations: jsonStrings(j['stations']),
        isDefaultSales: jsonBool(j, 'isDefaultSales'),
        itemCount: jsonInt(j, 'itemCount'),
        value: jsonDecimal(j, 'value', '0.00'),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'kind': kind,
        'stations': stations,
        'isDefaultSales': isDefaultSales,
      };
}

// --- stock items ------------------------------------------------------------

class StockItemRow {
  const StockItemRow({
    required this.id,
    required this.name,
    this.categoryName,
    required this.baseUnit,
    required this.packSize,
    required this.packName,
    required this.isLiquor,
    required this.isKeg,
    required this.onHand,
    required this.onHandDisplay,
    required this.parLevel,
    required this.parDisplay,
    required this.avgCost,
    required this.unitCostDisplay,
    required this.value,
    required this.status,
    this.locationId,
  });

  final String id;
  final String name;
  final String? categoryName;
  final String baseUnit;
  final num packSize;
  final String packName;
  final bool isLiquor;
  final bool isKeg;
  final String onHand;
  final String onHandDisplay;
  final String parLevel;
  final String parDisplay;
  final String avgCost;
  final String unitCostDisplay;
  final String value;
  final String status;
  final String? locationId;

  num get onHandQty => decimalValue(onHand);
  num get parQty => decimalValue(parLevel);
  num get avgCostAmount => decimalValue(avgCost);
  num get valueAmount => decimalValue(value);

  factory StockItemRow.fromJson(Map<String, dynamic> j) {
    final packSize = decimalValue(j['packSize']);
    return StockItemRow(
      id: jsonStr(j, 'id'),
      name: jsonStr(j, 'name'),
      categoryName: jsonStrOrNull(j, 'categoryName'),
      baseUnit: jsonStr(j, 'baseUnit', BaseUnits.ml),
      packSize: packSize == 0 ? 1 : packSize,
      packName: jsonStr(j, 'packName', 'pc'),
      isLiquor: jsonBool(j, 'isLiquor'),
      isKeg: jsonBool(j, 'isKeg'),
      onHand: jsonDecimal(j, 'onHand', '0.000'),
      onHandDisplay: jsonStr(j, 'onHandDisplay'),
      parLevel: jsonDecimal(j, 'parLevel', '0.000'),
      parDisplay: jsonStr(j, 'parDisplay'),
      avgCost: jsonDecimal(j, 'avgCost', '0.000000'),
      unitCostDisplay: jsonStr(j, 'unitCostDisplay'),
      value: jsonDecimal(j, 'value', '0.00'),
      status: jsonStr(j, 'status', StockStatus.ok),
      locationId: jsonStrOrNull(j, 'locationId'),
    );
  }
}

/// Editable fields of a stock item (PLAN 1.7 `StockItemInput`).
class StockItemInput {
  const StockItemInput({
    required this.name,
    this.sku,
    this.categoryName,
    this.baseUnit = BaseUnits.ml,
    this.packSize = 1,
    this.packName = 'pc',
    this.purchaseUnitName = 'Unit',
    this.purchaseUnitQty = 1,
    this.costingMethod = 'WEIGHTED_AVERAGE',
    this.preferredVendorId,
    this.isLiquor = false,
    this.isKeg = false,
    this.shelfLifeDays,
    this.isActive = true,
  });

  final String name;
  final String? sku;
  final String? categoryName;
  final String baseUnit;
  final num packSize;
  final String packName;
  final String purchaseUnitName;
  final num purchaseUnitQty;

  /// WEIGHTED_AVERAGE | FIFO (FIFO is stored; weighted average is computed).
  final String costingMethod;
  final String? preferredVendorId;
  final bool isLiquor;
  final bool isKeg;
  final int? shelfLifeDays;
  final bool isActive;

  factory StockItemInput.fromJson(Map<String, dynamic> j) {
    final packSize = decimalValue(j['packSize']);
    final purchaseQty = decimalValue(j['purchaseUnitQty']);
    return StockItemInput(
      name: jsonStr(j, 'name'),
      sku: jsonStrOrNull(j, 'sku'),
      categoryName: jsonStrOrNull(j, 'categoryName'),
      baseUnit: jsonStr(j, 'baseUnit', BaseUnits.ml),
      packSize: packSize == 0 ? 1 : packSize,
      packName: jsonStr(j, 'packName', 'pc'),
      purchaseUnitName: jsonStr(j, 'purchaseUnitName', 'Unit'),
      purchaseUnitQty: purchaseQty == 0 ? 1 : purchaseQty,
      costingMethod: jsonStr(j, 'costingMethod', 'WEIGHTED_AVERAGE'),
      preferredVendorId: jsonStrOrNull(j, 'preferredVendorId'),
      isLiquor: jsonBool(j, 'isLiquor'),
      isKeg: jsonBool(j, 'isKeg'),
      shelfLifeDays: jsonInt(j, 'shelfLifeDays') == 0 ? null : jsonInt(j, 'shelfLifeDays'),
      isActive: jsonBool(j, 'isActive', true),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'sku': sku,
        'categoryName': categoryName,
        'baseUnit': baseUnit,
        'packSize': packSize,
        'packName': packName,
        'purchaseUnitName': purchaseUnitName,
        'purchaseUnitQty': purchaseUnitQty,
        'costingMethod': costingMethod,
        'preferredVendorId': preferredVendorId,
        'isLiquor': isLiquor,
        'isKeg': isKeg,
        'shelfLifeDays': shelfLifeDays,
        'isActive': isActive,
      };
}

class StockLevelRow {
  const StockLevelRow({
    required this.locationId,
    required this.locationName,
    required this.onHand,
    required this.onHandDisplay,
    required this.parLevel,
  });

  final String locationId;
  final String locationName;
  final String onHand;
  final String onHandDisplay;
  final String parLevel;

  factory StockLevelRow.fromJson(Map<String, dynamic> j) => StockLevelRow(
        locationId: jsonStr(j, 'locationId'),
        locationName: jsonStr(j, 'locationName'),
        onHand: jsonDecimal(j, 'onHand', '0.000'),
        onHandDisplay: jsonStr(j, 'onHandDisplay'),
        parLevel: jsonDecimal(j, 'parLevel', '0.000'),
      );
}

/// `StockItemDetail = StockItemRow & StockItemInput & {...}`, read from one map.
class StockItemDetail {
  const StockItemDetail({
    required this.row,
    required this.input,
    this.preferredVendor,
    this.levels = const [],
    this.lastPurchaseRate,
  });

  final StockItemRow row;
  final StockItemInput input;
  final RefName? preferredVendor;
  final List<StockLevelRow> levels;
  final String? lastPurchaseRate;

  factory StockItemDetail.fromJson(Map<String, dynamic> j) => StockItemDetail(
        row: StockItemRow.fromJson(j),
        input: StockItemInput.fromJson(j),
        preferredVendor: RefName.maybe(j['preferredVendor']),
        levels: [for (final l in jsonMaps(j['levels'])) StockLevelRow.fromJson(l)],
        lastPurchaseRate: jsonDecimalOrNull(j, 'lastPurchaseRate'),
      );
}

class MovementRow {
  const MovementRow({
    required this.id,
    required this.type,
    required this.qty,
    required this.qtyDisplay,
    required this.unitCost,
    required this.value,
    this.refType,
    this.refId,
    this.note,
    required this.businessDate,
    this.createdAt,
    this.createdBy,
  });

  final String id;
  final String type;
  final String qty;
  final String qtyDisplay;
  final String unitCost;
  final String value;
  final String? refType;
  final String? refId;
  final String? note;
  final String businessDate;
  final DateTime? createdAt;
  final String? createdBy;

  factory MovementRow.fromJson(Map<String, dynamic> j) {
    final by = j['createdBy'];
    return MovementRow(
      id: jsonStr(j, 'id'),
      type: jsonStr(j, 'type'),
      qty: jsonDecimal(j, 'qty', '0.000'),
      qtyDisplay: jsonStr(j, 'qtyDisplay'),
      unitCost: jsonDecimal(j, 'unitCost', '0.000000'),
      value: jsonDecimal(j, 'value', '0.00'),
      refType: jsonStrOrNull(j, 'refType'),
      refId: jsonStrOrNull(j, 'refId'),
      note: jsonStrOrNull(j, 'note'),
      businessDate: jsonStr(j, 'businessDate'),
      createdAt: jsonDate(j, 'createdAt'),
      createdBy: by is Map ? RefName.maybe(by)?.name : by?.toString(),
    );
  }
}

// --- transfers --------------------------------------------------------------

class TransferLine {
  const TransferLine({
    required this.stockItemId,
    required this.name,
    required this.qty,
    required this.qtyDisplay,
    required this.value,
  });

  final String stockItemId;
  final String name;
  final String qty;
  final String qtyDisplay;
  final String value;

  factory TransferLine.fromJson(Map<String, dynamic> j) => TransferLine(
        stockItemId: jsonStr(j, 'stockItemId'),
        name: jsonStr(j, 'name'),
        qty: jsonDecimal(j, 'qty', '0.000'),
        qtyDisplay: jsonStr(j, 'qtyDisplay'),
        value: jsonDecimal(j, 'value', '0.00'),
      );
}

class TransferView {
  const TransferView({
    required this.id,
    required this.number,
    this.fromLocation,
    this.toLocation,
    this.note,
    this.createdAt,
    this.createdBy,
    this.lines = const [],
  });

  final String id;
  final String number;
  final RefName? fromLocation;
  final RefName? toLocation;
  final String? note;
  final DateTime? createdAt;
  final RefName? createdBy;
  final List<TransferLine> lines;

  factory TransferView.fromJson(Map<String, dynamic> j) => TransferView(
        id: jsonStr(j, 'id'),
        number: jsonStr(j, 'number'),
        fromLocation: RefName.maybe(j['fromLocation']),
        toLocation: RefName.maybe(j['toLocation']),
        note: jsonStrOrNull(j, 'note'),
        createdAt: jsonDate(j, 'createdAt'),
        createdBy: RefName.maybe(j['createdBy']),
        lines: [for (final l in jsonMaps(j['lines'])) TransferLine.fromJson(l)],
      );
}

// --- stock counts -----------------------------------------------------------

abstract final class CountStatus {
  static const open = 'OPEN';
  static const submitted = 'SUBMITTED';
  static const posted = 'POSTED';
  static const cancelled = 'CANCELLED';
}

class CountSummary {
  const CountSummary({
    required this.id,
    this.location,
    required this.status,
    required this.businessDate,
    this.startedBy,
    this.countedLines = 0,
    this.totalLines = 0,
    this.submittedAt,
    this.postedAt,
  });

  final String id;
  final RefName? location;
  final String status;
  final String businessDate;
  final RefName? startedBy;
  final int countedLines;
  final int totalLines;
  final DateTime? submittedAt;
  final DateTime? postedAt;

  factory CountSummary.fromJson(Map<String, dynamic> j) => CountSummary(
        id: jsonStr(j, 'id'),
        location: RefName.maybe(j['location']),
        status: jsonStr(j, 'status', CountStatus.open),
        businessDate: jsonStr(j, 'businessDate'),
        startedBy: RefName.maybe(j['startedBy']),
        countedLines: jsonInt(j, 'countedLines'),
        totalLines: jsonInt(j, 'totalLines'),
        submittedAt: jsonDate(j, 'submittedAt'),
        postedAt: jsonDate(j, 'postedAt'),
      );
}

class CountLine {
  const CountLine({
    required this.stockItemId,
    required this.name,
    required this.baseUnit,
    required this.packSize,
    required this.packName,
    this.countedQty,
    this.countedDisplay,
    this.expectedQty,
    this.expectedDisplay,
    this.differencePercent,
    this.outlier = false,
    this.confirmedOutlier = false,
    this.note,
    this.countedAt,
  });

  final String stockItemId;
  final String name;
  final String baseUnit;
  final num packSize;
  final String packName;

  /// Null when not counted yet.
  final String? countedQty;
  final String? countedDisplay;

  /// Snapshot at submit. Null before submit.
  final String? expectedQty;
  final String? expectedDisplay;

  /// Null until both counted and expected are known.
  final num? differencePercent;
  final bool outlier;
  final bool confirmedOutlier;
  final String? note;
  final DateTime? countedAt;

  factory CountLine.fromJson(Map<String, dynamic> j) {
    final packSize = decimalValue(j['packSize']);
    return CountLine(
      stockItemId: jsonStr(j, 'stockItemId'),
      name: jsonStr(j, 'name'),
      baseUnit: jsonStr(j, 'baseUnit', BaseUnits.ml),
      packSize: packSize == 0 ? 1 : packSize,
      packName: jsonStr(j, 'packName', 'pc'),
      countedQty: jsonDecimalOrNull(j, 'countedQty'),
      countedDisplay: jsonStrOrNull(j, 'countedDisplay'),
      expectedQty: jsonDecimalOrNull(j, 'expectedQty'),
      expectedDisplay: jsonStrOrNull(j, 'expectedDisplay'),
      differencePercent: decimalOrNull(j['differencePercent']),
      outlier: jsonBool(j, 'outlier'),
      confirmedOutlier: jsonBool(j, 'confirmedOutlier'),
      note: jsonStrOrNull(j, 'note'),
      countedAt: jsonDate(j, 'countedAt'),
    );
  }
}

class CountView {
  const CountView({
    required this.summary,
    this.lines = const [],
    this.varianceValue,
  });

  final CountSummary summary;
  final List<CountLine> lines;

  /// Set after post.
  final String? varianceValue;

  String get id => summary.id;
  String get status => summary.status;

  factory CountView.fromJson(Map<String, dynamic> j) => CountView(
        summary: CountSummary.fromJson(j),
        lines: [for (final l in jsonMaps(j['lines'])) CountLine.fromJson(l)],
        varianceValue: jsonDecimalOrNull(j, 'varianceValue'),
      );
}

// --- wastage ----------------------------------------------------------------

/// Wire values of `WastageReason` a user may pick.
abstract final class WastageReasons {
  static const broken = 'BROKEN';
  static const spilled = 'SPILLED';
  static const expired = 'EXPIRED';
  static const comp = 'COMP';
  static const staffMeal = 'STAFF_MEAL';
  static const burnt = 'BURNT';
  static const dropped = 'DROPPED';
  static const returned = 'RETURNED';

  /// Label for each reason the wastage sheet offers, in board order.
  static const picks = <(String, String)>[
    (broken, 'Broken'),
    (spilled, 'Spilled'),
    (expired, 'Expired'),
    (comp, 'Comp'),
    (staffMeal, 'Staff meal'),
    (burnt, 'Burnt'),
    (dropped, 'Dropped'),
    (returned, 'Returned'),
  ];

  static String label(String reason) {
    for (final (wire, text) in picks) {
      if (wire == reason) return text;
    }
    return reason == 'VOID'
        ? 'Void'
        : reason == 'DAMAGED_DELIVERY'
            ? 'Damaged delivery'
            : reason.toLowerCase();
  }
}

class WastageView {
  const WastageView({
    required this.id,
    this.location,
    this.stockItem,
    required this.qty,
    required this.qtyDisplay,
    required this.value,
    required this.reason,
    this.note,
    this.photoUrl,
    this.createdAt,
    this.createdBy,
  });

  final String id;
  final RefName? location;
  final RefName? stockItem;
  final String qty;
  final String qtyDisplay;
  final String value;
  final String reason;
  final String? note;
  final String? photoUrl;
  final DateTime? createdAt;
  final RefName? createdBy;

  factory WastageView.fromJson(Map<String, dynamic> j) => WastageView(
        id: jsonStr(j, 'id'),
        location: RefName.maybe(j['location']),
        stockItem: RefName.maybe(j['stockItem']),
        qty: jsonDecimal(j, 'qty', '0.000'),
        qtyDisplay: jsonStr(j, 'qtyDisplay'),
        value: jsonDecimal(j, 'value', '0.00'),
        reason: jsonStr(j, 'reason'),
        note: jsonStrOrNull(j, 'note'),
        photoUrl: jsonStrOrNull(j, 'photoUrl'),
        createdAt: jsonDate(j, 'createdAt'),
        createdBy: RefName.maybe(j['createdBy']),
      );
}

/// `GET /stock/wastage` response: rows plus header totals.
class WastageList {
  const WastageList({this.items = const [], this.totalValue = '0.00'});

  final List<WastageView> items;
  final String totalValue;

  factory WastageList.fromJson(Map<String, dynamic> j) => WastageList(
        items: [for (final w in jsonMaps(j['items'])) WastageView.fromJson(w)],
        totalValue: jsonDecimal(j, 'totalValue', '0.00'),
      );
}

// --- variance ---------------------------------------------------------------

class VarianceRow {
  const VarianceRow({
    required this.stockItemId,
    required this.name,
    required this.baseUnit,
    required this.opening,
    required this.received,
    required this.sold,
    required this.wastage,
    required this.expected,
    this.counted,
    required this.variance,
    required this.varianceDisplay,
    required this.varianceValue,
    required this.unitCost,
    required this.openingDisplay,
    required this.receivedDisplay,
    required this.soldDisplay,
    required this.wastageDisplay,
    required this.expectedDisplay,
    this.countedDisplay,
  });

  final String stockItemId;
  final String name;
  final String baseUnit;
  final String opening;
  final String received;
  final String sold;
  final String wastage;
  final String expected;
  final String? counted;
  final String variance;
  final String varianceDisplay;
  final String varianceValue;
  final String unitCost;
  final String openingDisplay;
  final String receivedDisplay;
  final String soldDisplay;
  final String wastageDisplay;
  final String expectedDisplay;
  final String? countedDisplay;

  factory VarianceRow.fromJson(Map<String, dynamic> j) => VarianceRow(
        stockItemId: jsonStr(j, 'stockItemId'),
        name: jsonStr(j, 'name'),
        baseUnit: jsonStr(j, 'baseUnit', BaseUnits.ml),
        opening: jsonDecimal(j, 'opening', '0.000'),
        received: jsonDecimal(j, 'received', '0.000'),
        sold: jsonDecimal(j, 'sold', '0.000'),
        wastage: jsonDecimal(j, 'wastage', '0.000'),
        expected: jsonDecimal(j, 'expected', '0.000'),
        counted: jsonDecimalOrNull(j, 'counted'),
        variance: jsonDecimal(j, 'variance', '0.000'),
        varianceDisplay: jsonStr(j, 'varianceDisplay'),
        varianceValue: jsonDecimal(j, 'varianceValue', '0.00'),
        unitCost: jsonDecimal(j, 'unitCost', '0.000000'),
        openingDisplay: jsonStr(j, 'openingDisplay'),
        receivedDisplay: jsonStr(j, 'receivedDisplay'),
        soldDisplay: jsonStr(j, 'soldDisplay'),
        wastageDisplay: jsonStr(j, 'wastageDisplay'),
        expectedDisplay: jsonStr(j, 'expectedDisplay'),
        countedDisplay: jsonStrOrNull(j, 'countedDisplay'),
      );
}

class VarianceReport {
  const VarianceReport({
    required this.from,
    required this.to,
    this.rows = const [],
    this.totalVarianceValue = '0.00',
  });

  final String from;
  final String to;
  final List<VarianceRow> rows;
  final String totalVarianceValue;

  factory VarianceReport.fromJson(Map<String, dynamic> j) {
    final totals = jsonMap(j['totals']);
    return VarianceReport(
      from: jsonStr(j, 'from'),
      to: jsonStr(j, 'to'),
      rows: [for (final r in jsonMaps(j['rows'])) VarianceRow.fromJson(r)],
      totalVarianceValue: jsonDecimal(totals, 'varianceValue', '0.00'),
    );
  }
}

// --- kegs -------------------------------------------------------------------

class KegLocation {
  const KegLocation({
    required this.locationId,
    required this.name,
    required this.qty,
    required this.qtyDisplay,
  });

  final String locationId;
  final String name;
  final String qty;
  final String qtyDisplay;

  factory KegLocation.fromJson(Map<String, dynamic> j) => KegLocation(
        locationId: jsonStr(j, 'locationId'),
        name: jsonStr(j, 'name'),
        qty: jsonDecimal(j, 'qty', '0.000'),
        qtyDisplay: jsonStr(j, 'qtyDisplay'),
      );
}

class KegRow {
  const KegRow({
    required this.stockItemId,
    required this.name,
    required this.fullKegs,
    required this.onTapMl,
    required this.onTapDisplay,
    this.locationBreakdown = const [],
  });

  final String stockItemId;
  final String name;
  final int fullKegs;
  final String onTapMl;
  final String onTapDisplay;
  final List<KegLocation> locationBreakdown;

  factory KegRow.fromJson(Map<String, dynamic> j) => KegRow(
        stockItemId: jsonStr(j, 'stockItemId'),
        name: jsonStr(j, 'name'),
        fullKegs: jsonInt(j, 'fullKegs'),
        onTapMl: jsonDecimal(j, 'onTapMl', '0.000'),
        onTapDisplay: jsonStr(j, 'onTapDisplay'),
        locationBreakdown: [
          for (final l in jsonMaps(j['locationBreakdown'])) KegLocation.fromJson(l),
        ],
      );
}

// --- recipes ----------------------------------------------------------------

class RecipeLineView {
  const RecipeLineView({
    required this.stockItemId,
    required this.name,
    required this.baseUnit,
    required this.qty,
    required this.wastagePercent,
    required this.cost,
  });

  final String stockItemId;
  final String name;
  final String baseUnit;
  final String qty;
  final String wastagePercent;
  final String cost;

  factory RecipeLineView.fromJson(Map<String, dynamic> j) => RecipeLineView(
        stockItemId: jsonStr(j, 'stockItemId'),
        name: jsonStr(j, 'name'),
        baseUnit: jsonStr(j, 'baseUnit', BaseUnits.ml),
        qty: jsonDecimal(j, 'qty', '0.000'),
        wastagePercent: jsonDecimal(j, 'wastagePercent', '0.00'),
        cost: jsonDecimal(j, 'cost', '0.00'),
      );
}

class RecipeView {
  const RecipeView({
    this.variantId,
    this.variantName,
    this.note,
    this.lines = const [],
    this.costPerServing = '0.00',
    this.sellingPrice = '0.00',
    this.pourCostPercent,
    this.marginPercent,
  });

  /// Null for the "All variants" recipe.
  final String? variantId;
  final String? variantName;
  final String? note;
  final List<RecipeLineView> lines;
  final String costPerServing;
  final String sellingPrice;
  final String? pourCostPercent;
  final String? marginPercent;

  factory RecipeView.fromJson(Map<String, dynamic> j) => RecipeView(
        variantId: jsonStrOrNull(j, 'variantId'),
        variantName: jsonStrOrNull(j, 'variantName'),
        note: jsonStrOrNull(j, 'note'),
        lines: [for (final l in jsonMaps(j['lines'])) RecipeLineView.fromJson(l)],
        costPerServing: jsonDecimal(j, 'costPerServing', '0.00'),
        sellingPrice: jsonDecimal(j, 'sellingPrice', '0.00'),
        pourCostPercent: jsonDecimalOrNull(j, 'pourCostPercent'),
        marginPercent: jsonDecimalOrNull(j, 'marginPercent'),
      );
}

// --- request bodies ---------------------------------------------------------

class RecipeLineInput {
  const RecipeLineInput({required this.stockItemId, required this.qty, this.wastagePercent = 0});

  final String stockItemId;

  /// Base units per serving.
  final num qty;
  final num wastagePercent;

  Map<String, dynamic> toJson() => {
        'stockItemId': stockItemId,
        'qty': qty,
        'wastagePercent': wastagePercent,
      };
}

class RecipeInput {
  const RecipeInput({this.variantId, this.note, this.lines = const []});

  final String? variantId;
  final String? note;
  final List<RecipeLineInput> lines;

  Map<String, dynamic> toJson() => {
        'variantId': variantId,
        'note': note,
        'lines': [for (final l in lines) l.toJson()],
      };
}

/// One line of a count save. `countedQty` is the wire string, or null for
/// "not counted".
class CountLineInput {
  const CountLineInput({
    required this.stockItemId,
    this.countedQty,
    this.note,
    this.confirmedOutlier = false,
    this.countedAt,
  });

  final String stockItemId;
  final String? countedQty;
  final String? note;
  final bool confirmedOutlier;
  final DateTime? countedAt;

  Map<String, dynamic> toJson() => {
        'stockItemId': stockItemId,
        'countedQty': countedQty,
        'note': note,
        'confirmedOutlier': confirmedOutlier,
        'countedAt': countedAt?.toUtc().toIso8601String(),
      };
}

/// Quantity in base units for a stock item, as the count and wastage screens
/// read it: whole packs plus an open part.
String displayQty(num qty, StockItemRow item) =>
    formatStockQty(qty, item.baseUnit, item.packSize, item.packName);
