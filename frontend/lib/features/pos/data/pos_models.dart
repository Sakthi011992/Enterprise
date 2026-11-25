/// POS data models (PLAN 1.4 and 1.7). Every `fromJson` is tolerant of missing
/// optional keys and of money sent as a number instead of a string.
///
/// Money convention: fields keep the wire form (`String`, two decimals). Numeric
/// views are the `...Value` getters. Use them only for display and for
/// client-side validation. The server totals are the ones shown to staff.
library;

// --- JSON helpers ------------------------------------------------------------

Map<String, dynamic> asMap(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> asMaps(Object? v) => [
      for (final e in (v as List?) ?? const []) asMap(e),
    ];

List<String> asStrings(Object? v) => [
      for (final e in (v as List?) ?? const []) e.toString(),
    ];

String readString(Map<String, dynamic> j, String key, [String fallback = '']) {
  final v = j[key];
  return v == null ? fallback : v.toString();
}

String? readStringOrNull(Map<String, dynamic> j, String key) {
  final v = j[key];
  return v == null ? null : v.toString();
}

int readInt(Map<String, dynamic> j, String key, [int fallback = 0]) {
  final v = j[key];
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

int? readIntOrNull(Map<String, dynamic> j, String key) {
  final v = j[key];
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

bool readBool(Map<String, dynamic> j, String key, [bool fallback = false]) {
  final v = j[key];
  return v is bool ? v : fallback;
}

/// Money from the wire: always a string with two decimals.
String readMoney(Map<String, dynamic> j, String key, [String fallback = '0.00']) =>
    moneyText(j[key], fallback: fallback);

String? readMoneyOrNull(Map<String, dynamic> j, String key) {
  final v = j[key];
  if (v == null) return null;
  return moneyText(v);
}

String moneyText(Object? v, {String fallback = '0.00'}) {
  if (v == null) return fallback;
  if (v is num) return v.toStringAsFixed(2);
  final parsed = num.tryParse(v.toString());
  return parsed == null ? fallback : parsed.toStringAsFixed(2);
}

num moneyValue(String text) => num.tryParse(text) ?? 0;

DateTime? readDate(Map<String, dynamic> j, String key) {
  final v = j[key];
  return v is String ? DateTime.tryParse(v) : null;
}

// --- order type and wire constants ------------------------------------------

/// Wire values for `OrderType`.
abstract final class OrderTypes {
  static const dineIn = 'DINE_IN';
  static const barCounter = 'BAR_COUNTER';
  static const takeaway = 'TAKEAWAY';
  static const delivery = 'DELIVERY';

  static const all = [dineIn, barCounter, takeaway, delivery];

  static String label(String type) => switch (type) {
        dineIn => 'Dine-in',
        barCounter => 'Bar counter',
        takeaway => 'Takeaway',
        delivery => 'Delivery',
        _ => type,
      };
}

/// Wire values for `OrderStatus` (legacy values included for old rows).
abstract final class OrderStatuses {
  static const open = 'OPEN';
  static const sent = 'SENT';
  static const billed = 'BILLED';
  static const paid = 'PAID';
  static const closed = 'CLOSED';
  static const voided = 'VOID';
  static const refunded = 'REFUNDED';
}

/// Wire values for `OrderItemStatus`.
abstract final class ItemStatuses {
  static const newItem = 'NEW';
  static const sent = 'SENT';
  static const served = 'SERVED';
  static const voided = 'VOIDED';
}

/// Wire values for `ApprovalType`.
abstract final class ApprovalTypes {
  static const discount = 'DISCOUNT';
  static const void_ = 'VOID';
  static const refund = 'REFUND';
  static const noSale = 'NO_SALE';
}

/// Wire values for `ApprovalStatus`.
abstract final class ApprovalStatuses {
  static const pending = 'PENDING';
  static const approved = 'APPROVED';
  static const declined = 'DECLINED';
  static const expired = 'EXPIRED';
}

/// Payment method values sent to `POST /orders/:id/payments`.
abstract final class PaymentMethods {
  static const cash = 'CASH';
  static const upi = 'UPI';
  static const card = 'CARD';
}

// --- menu (GET /menu/pos) ----------------------------------------------------

class PosCategory {
  const PosCategory({
    required this.id,
    required this.name,
    this.color,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final String? color;
  final int sortOrder;

  factory PosCategory.fromJson(Map<String, dynamic> j) => PosCategory(
        id: readString(j, 'id'),
        name: readString(j, 'name'),
        color: readStringOrNull(j, 'color'),
        sortOrder: readInt(j, 'sortOrder'),
      );
}

class PosVariant {
  const PosVariant({
    required this.id,
    required this.name,
    required this.price,
    this.isDefault = false,
  });

  final String id;
  final String name;
  final String price;
  final bool isDefault;

  num get priceValue => moneyValue(price);

  factory PosVariant.fromJson(Map<String, dynamic> j) => PosVariant(
        id: readString(j, 'id'),
        name: readString(j, 'name'),
        price: readMoney(j, 'price'),
        isDefault: readBool(j, 'isDefault'),
      );
}

class PosProduct {
  const PosProduct({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.price,
    this.is86 = false,
    this.imageUrl,
    this.taxClassId,
    this.variants = const [],
    this.modifierGroupIds = const [],
  });

  final String id;
  final String name;
  final String? categoryId;
  final String price;
  final bool is86;
  final String? imageUrl;
  final String? taxClassId;
  final List<PosVariant> variants;
  final List<String> modifierGroupIds;

  num get priceValue => moneyValue(price);

  /// The variant tapped on the card, or null when the product has none.
  PosVariant? get defaultVariant {
    if (variants.isEmpty) return null;
    for (final v in variants) {
      if (v.isDefault) return v;
    }
    return variants.first;
  }

  factory PosProduct.fromJson(Map<String, dynamic> j) => PosProduct(
        id: readString(j, 'id'),
        name: readString(j, 'name'),
        categoryId: readStringOrNull(j, 'categoryId'),
        price: readMoney(j, 'price'),
        is86: readBool(j, 'is86'),
        imageUrl: readStringOrNull(j, 'imageUrl'),
        taxClassId: readStringOrNull(j, 'taxClassId'),
        variants: [for (final v in asMaps(j['variants'])) PosVariant.fromJson(v)],
        modifierGroupIds: asStrings(j['modifierGroupIds']),
      );
}

class PosModifierOption {
  const PosModifierOption({
    required this.id,
    required this.name,
    this.priceDelta = '0.00',
  });

  final String id;
  final String name;
  final String priceDelta;

  num get priceDeltaValue => moneyValue(priceDelta);

  factory PosModifierOption.fromJson(Map<String, dynamic> j) => PosModifierOption(
        id: readString(j, 'id'),
        name: readString(j, 'name'),
        priceDelta: readMoney(j, 'priceDelta'),
      );
}

class PosModifierGroup {
  const PosModifierGroup({
    required this.id,
    required this.name,
    this.minSelect = 0,
    this.maxSelect = 1,
    this.options = const [],
  });

  final String id;
  final String name;
  final int minSelect;
  final int maxSelect;
  final List<PosModifierOption> options;

  /// A group with a max of one option is a radio group in the sheet.
  bool get isSingleChoice => maxSelect == 1;

  factory PosModifierGroup.fromJson(Map<String, dynamic> j) => PosModifierGroup(
        id: readString(j, 'id'),
        name: readString(j, 'name'),
        minSelect: readInt(j, 'minSelect'),
        maxSelect: readInt(j, 'maxSelect', 1),
        options: [for (final o in asMaps(j['options'])) PosModifierOption.fromJson(o)],
      );
}

class PosCombo {
  const PosCombo({
    required this.id,
    required this.name,
    required this.price,
    this.items = const [],
    this.availableNow = true,
  });

  final String id;
  final String name;
  final String price;
  final List<Map<String, dynamic>> items;
  final bool availableNow;

  num get priceValue => moneyValue(price);

  factory PosCombo.fromJson(Map<String, dynamic> j) => PosCombo(
        id: readString(j, 'id'),
        name: readString(j, 'name'),
        price: readMoney(j, 'price'),
        items: asMaps(j['items']),
        availableNow: readBool(j, 'availableNow', true),
      );
}

class PosPriceRule {
  const PosPriceRule({
    required this.id,
    required this.name,
    required this.percentOff,
    this.categoryIds = const [],
    this.productIds = const [],
    this.activeNow = false,
    this.endsAt,
  });

  final String id;
  final String name;
  final String percentOff;
  final List<String> categoryIds;
  final List<String> productIds;
  final bool activeNow;

  /// Parsed `endsAt` (outlet local time as sent by the server), or null.
  final DateTime? endsAt;

  num get percentOffValue => moneyValue(percentOff);

  factory PosPriceRule.fromJson(Map<String, dynamic> j) => PosPriceRule(
        id: readString(j, 'id'),
        name: readString(j, 'name'),
        percentOff: readMoney(j, 'percentOff', '0.00'),
        categoryIds: asStrings(j['categoryIds']),
        productIds: asStrings(j['productIds']),
        activeNow: readBool(j, 'activeNow'),
        endsAt: readDate(j, 'endsAt'),
      );
}

class PosTaxClass {
  const PosTaxClass({
    required this.id,
    required this.code,
    required this.name,
    required this.rate,
    this.isLiquor = false,
    this.inclusive = false,
  });

  final String id;
  final String code;
  final String name;
  final num rate;
  final bool isLiquor;
  final bool inclusive;

  factory PosTaxClass.fromJson(Map<String, dynamic> j) => PosTaxClass(
        id: readString(j, 'id'),
        code: readString(j, 'code'),
        name: readString(j, 'name'),
        rate: moneyValue(readMoney(j, 'rate', '0')),
        isLiquor: readBool(j, 'isLiquor'),
        inclusive: readBool(j, 'inclusive'),
      );
}

class PosSettings {
  const PosSettings({
    this.serviceChargePercent = '0.00',
    this.serviceChargeTypes = const [],
    this.roundingMode = 'NEAREST_1',
  });

  final String serviceChargePercent;
  final List<String> serviceChargeTypes;
  final String roundingMode;

  num get serviceChargePercentValue => moneyValue(serviceChargePercent);

  factory PosSettings.fromJson(Map<String, dynamic> j) => PosSettings(
        serviceChargePercent: readMoney(j, 'serviceChargePercent', '0.00'),
        serviceChargeTypes: asStrings(j['serviceChargeTypes']),
        roundingMode: readString(j, 'roundingMode', 'NEAREST_1'),
      );
}

/// Everything the POS needs, from `GET /menu/pos`.
class PosMenu {
  const PosMenu({
    this.categories = const [],
    this.products = const [],
    this.modifierGroups = const [],
    this.combos = const [],
    this.priceRules = const [],
    this.taxClasses = const [],
    this.settings = const PosSettings(),
  });

  final List<PosCategory> categories;
  final List<PosProduct> products;
  final List<PosModifierGroup> modifierGroups;
  final List<PosCombo> combos;
  final List<PosPriceRule> priceRules;
  final List<PosTaxClass> taxClasses;
  final PosSettings settings;

  PosProduct? productById(String id) {
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Modifier groups linked to [product], in the order the product lists them.
  List<PosModifierGroup> groupsFor(PosProduct product) {
    final byId = {for (final g in modifierGroups) g.id: g};
    return [
      for (final id in product.modifierGroupIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

  /// Happy-hour rules active right now.
  List<PosPriceRule> get activeHappyHours =>
      [for (final r in priceRules) if (r.activeNow) r];

  factory PosMenu.fromJson(Map<String, dynamic> j) => PosMenu(
        categories: [for (final c in asMaps(j['categories'])) PosCategory.fromJson(c)],
        products: [for (final p in asMaps(j['products'])) PosProduct.fromJson(p)],
        modifierGroups: [
          for (final g in asMaps(j['modifierGroups'])) PosModifierGroup.fromJson(g),
        ],
        combos: [for (final c in asMaps(j['combos'])) PosCombo.fromJson(c)],
        priceRules: [for (final r in asMaps(j['priceRules'])) PosPriceRule.fromJson(r)],
        taxClasses: [for (final t in asMaps(j['taxClasses'])) PosTaxClass.fromJson(t)],
        settings: PosSettings.fromJson(asMap(j['settings'])),
      );
}

// --- orders (OrderView, PLAN 1.4) --------------------------------------------

class TableRef {
  const TableRef({required this.id, required this.name, this.areaName});

  final String id;
  final String name;
  final String? areaName;

  factory TableRef.fromJson(Map<String, dynamic> j) => TableRef(
        id: readString(j, 'id'),
        name: readString(j, 'name'),
        areaName: readStringOrNull(j, 'areaName'),
      );
}

class WaiterRef {
  const WaiterRef({required this.id, required this.name});

  final String id;
  final String name;

  factory WaiterRef.fromJson(Map<String, dynamic> j) =>
      WaiterRef(id: readString(j, 'id'), name: readString(j, 'name'));
}

class OrderItemModifier {
  const OrderItemModifier({
    required this.optionId,
    required this.name,
    this.priceDelta = '0.00',
  });

  final String optionId;
  final String name;
  final String priceDelta;

  factory OrderItemModifier.fromJson(Map<String, dynamic> j) => OrderItemModifier(
        optionId: readString(j, 'optionId'),
        name: readString(j, 'name'),
        priceDelta: readMoney(j, 'priceDelta'),
      );
}

class TaxLine {
  const TaxLine({required this.name, required this.rate, required this.amount});

  final String name;
  final num rate;
  final String amount;

  num get amountValue => moneyValue(amount);

  factory TaxLine.fromJson(Map<String, dynamic> j) => TaxLine(
        name: readString(j, 'name'),
        rate: moneyValue(readMoney(j, 'rate', '0')),
        amount: readMoney(j, 'amount'),
      );
}

class OrderItemView {
  const OrderItemView({
    required this.id,
    this.productId,
    this.comboId,
    required this.name,
    this.variantName,
    this.seat,
    required this.quantity,
    required this.status,
    this.modifiers = const [],
    this.note,
    required this.unitPrice,
    required this.gross,
    required this.discount,
    required this.net,
    required this.tax,
    required this.total,
    this.happyHourPercent,
    this.isLiquor = false,
    this.ticketKind,
    this.station,
    this.sentAt,
  });

  final String id;
  final String? productId;
  final String? comboId;
  final String name;
  final String? variantName;
  final int? seat;
  final int quantity;

  /// One of [ItemStatuses].
  final String status;
  final List<OrderItemModifier> modifiers;
  final String? note;
  final String unitPrice;
  final String gross;
  final String discount;
  final String net;
  final String tax;
  final String total;
  final String? happyHourPercent;
  final bool isLiquor;

  /// `KOT` or `BOT` once sent.
  final String? ticketKind;
  final String? station;
  final DateTime? sentAt;

  bool get isNew => status == ItemStatuses.newItem;
  bool get isSent => status == ItemStatuses.sent || status == ItemStatuses.served;
  bool get isVoided => status == ItemStatuses.voided;
  bool get hasHappyHour => happyHourPercent != null && moneyValue(happyHourPercent!) > 0;

  num get unitPriceValue => moneyValue(unitPrice);
  num get grossValue => moneyValue(gross);
  num get totalValue => moneyValue(total);

  /// Names of the chosen modifiers, for the ticket line.
  String get modifierSummary => modifiers.map((m) => m.name).join(' · ');

  factory OrderItemView.fromJson(Map<String, dynamic> j) => OrderItemView(
        id: readString(j, 'id'),
        productId: readStringOrNull(j, 'productId'),
        comboId: readStringOrNull(j, 'comboId'),
        name: readString(j, 'name'),
        variantName: readStringOrNull(j, 'variantName'),
        seat: readIntOrNull(j, 'seat'),
        quantity: readInt(j, 'quantity', 1),
        status: readString(j, 'status', ItemStatuses.newItem),
        modifiers: [for (final m in asMaps(j['modifiers'])) OrderItemModifier.fromJson(m)],
        note: readStringOrNull(j, 'note'),
        unitPrice: readMoney(j, 'unitPrice'),
        gross: readMoney(j, 'gross'),
        discount: readMoney(j, 'discount'),
        net: readMoney(j, 'net'),
        tax: readMoney(j, 'tax'),
        total: readMoney(j, 'total'),
        happyHourPercent: readMoneyOrNull(j, 'happyHourPercent'),
        isLiquor: readBool(j, 'isLiquor'),
        ticketKind: readStringOrNull(j, 'ticketKind'),
        station: readStringOrNull(j, 'station'),
        sentAt: readDate(j, 'sentAt'),
      );
}

class DiscountView {
  const DiscountView({
    required this.id,
    required this.type,
    required this.value,
    this.itemIds = const [],
    required this.amount,
    required this.reason,
    this.approvedBy,
  });

  final String id;

  /// `PERCENT` or `FLAT`.
  final String type;
  final String value;
  final List<String> itemIds;
  final String amount;
  final String reason;
  final String? approvedBy;

  bool get isWholeBill => itemIds.isEmpty;
  num get amountValue => moneyValue(amount);

  factory DiscountView.fromJson(Map<String, dynamic> j) => DiscountView(
        id: readString(j, 'id'),
        type: readString(j, 'type', 'PERCENT'),
        value: readMoney(j, 'value'),
        itemIds: asStrings(j['itemIds']),
        amount: readMoney(j, 'amount'),
        reason: readString(j, 'reason'),
        approvedBy: readStringOrNull(j, 'approvedBy'),
      );
}

class PaymentView {
  const PaymentView({
    required this.id,
    required this.method,
    required this.amount,
    this.tipAmount = '0.00',
    this.tendered,
    this.changeGiven,
    this.reference,
    this.seat,
    required this.status,
    this.createdAt,
  });

  final String id;
  final String method;
  final String amount;
  final String tipAmount;
  final String? tendered;
  final String? changeGiven;
  final String? reference;
  final int? seat;
  final String status;
  final DateTime? createdAt;

  num get amountValue => moneyValue(amount);
  num get tipValue => moneyValue(tipAmount);

  factory PaymentView.fromJson(Map<String, dynamic> j) => PaymentView(
        id: readString(j, 'id'),
        method: readString(j, 'method'),
        amount: readMoney(j, 'amount'),
        tipAmount: readMoney(j, 'tipAmount'),
        tendered: readMoneyOrNull(j, 'tendered'),
        changeGiven: readMoneyOrNull(j, 'changeGiven'),
        reference: readStringOrNull(j, 'reference'),
        seat: readIntOrNull(j, 'seat'),
        status: readString(j, 'status'),
        createdAt: readDate(j, 'createdAt'),
      );
}

class OrderTotals {
  const OrderTotals({
    this.subtotal = '0.00',
    this.discountTotal = '0.00',
    this.netSubtotal = '0.00',
    this.serviceCharge = '0.00',
    this.taxTotal = '0.00',
    this.taxBreakdown = const [],
    this.roundOff = '0.00',
    this.grandTotal = '0.00',
    this.paid = '0.00',
    this.due = '0.00',
    this.tipTotal = '0.00',
  });

  final String subtotal;
  final String discountTotal;
  final String netSubtotal;
  final String serviceCharge;
  final String taxTotal;
  final List<TaxLine> taxBreakdown;
  final String roundOff;
  final String grandTotal;
  final String paid;
  final String due;
  final String tipTotal;

  num get grandTotalValue => moneyValue(grandTotal);
  num get paidValue => moneyValue(paid);
  num get dueValue => moneyValue(due);

  factory OrderTotals.fromJson(Map<String, dynamic> j) => OrderTotals(
        subtotal: readMoney(j, 'subtotal'),
        discountTotal: readMoney(j, 'discountTotal'),
        netSubtotal: readMoney(j, 'netSubtotal'),
        serviceCharge: readMoney(j, 'serviceCharge'),
        taxTotal: readMoney(j, 'taxTotal'),
        taxBreakdown: [for (final t in asMaps(j['taxBreakdown'])) TaxLine.fromJson(t)],
        roundOff: readMoney(j, 'roundOff'),
        grandTotal: readMoney(j, 'grandTotal'),
        paid: readMoney(j, 'paid'),
        due: readMoney(j, 'due'),
        tipTotal: readMoney(j, 'tipTotal'),
      );
}

class OrderView {
  const OrderView({
    required this.id,
    required this.orderNumber,
    required this.type,
    required this.status,
    this.table,
    this.covers = 1,
    this.waiter,
    this.openedAt,
    this.heldAt,
    this.billedAt,
    this.paidAt,
    this.note,
    this.items = const [],
    this.discounts = const [],
    this.payments = const [],
    required this.totals,
    this.invoiceNumber,
  });

  final String id;
  final String orderNumber;
  final String type;
  final String status;
  final TableRef? table;
  final int covers;
  final WaiterRef? waiter;
  final DateTime? openedAt;
  final DateTime? heldAt;
  final DateTime? billedAt;
  final DateTime? paidAt;
  final String? note;
  final List<OrderItemView> items;
  final List<DiscountView> discounts;
  final List<PaymentView> payments;
  final OrderTotals totals;
  final String? invoiceNumber;

  bool get isHeld => heldAt != null;
  bool get isOpen => status == OrderStatuses.open || status == OrderStatuses.sent || status == OrderStatuses.billed;
  bool get isPaid => status == OrderStatuses.paid || status == OrderStatuses.closed;

  /// Items that still count toward the bill.
  List<OrderItemView> get liveItems => [for (final i in items) if (!i.isVoided) i];

  /// Items not yet sent to a station.
  List<OrderItemView> get newItems => [for (final i in items) if (i.isNew) i];

  bool get hasUnsent => newItems.isNotEmpty;

  factory OrderView.fromJson(Map<String, dynamic> j) {
    final table = j['table'];
    final waiter = j['waiter'];
    return OrderView(
      id: readString(j, 'id'),
      orderNumber: readString(j, 'orderNumber'),
      type: readString(j, 'type', OrderTypes.takeaway),
      status: readString(j, 'status', OrderStatuses.open),
      table: table is Map ? TableRef.fromJson(asMap(table)) : null,
      covers: readInt(j, 'covers', 1),
      waiter: waiter is Map ? WaiterRef.fromJson(asMap(waiter)) : null,
      openedAt: readDate(j, 'openedAt'),
      heldAt: readDate(j, 'heldAt'),
      billedAt: readDate(j, 'billedAt'),
      paidAt: readDate(j, 'paidAt'),
      note: readStringOrNull(j, 'note'),
      items: [for (final i in asMaps(j['items'])) OrderItemView.fromJson(i)],
      discounts: [for (final d in asMaps(j['discounts'])) DiscountView.fromJson(d)],
      payments: [for (final p in asMaps(j['payments'])) PaymentView.fromJson(p)],
      totals: OrderTotals.fromJson(asMap(j['totals'])),
      invoiceNumber: readStringOrNull(j, 'invoiceNumber'),
    );
  }
}

/// Light row from `GET /orders/open`.
class OpenOrderSummary {
  const OpenOrderSummary({
    required this.id,
    required this.orderNumber,
    required this.type,
    required this.status,
    this.tableName,
    this.covers,
    this.grandTotal,
  });

  final String id;
  final String orderNumber;
  final String type;
  final String status;
  final String? tableName;
  final int? covers;
  final String? grandTotal;

  factory OpenOrderSummary.fromJson(Map<String, dynamic> j) {
    final table = asMap(j['table']);
    return OpenOrderSummary(
      id: readString(j, 'id'),
      orderNumber: readString(j, 'orderNumber'),
      type: readString(j, 'type', OrderTypes.takeaway),
      status: readString(j, 'status', OrderStatuses.open),
      tableName: table.isEmpty ? null : readStringOrNull(table, 'name'),
      covers: readIntOrNull(j, 'covers'),
      grandTotal: readMoneyOrNull(j, 'grandTotal'),
    );
  }
}

// --- requests ----------------------------------------------------------------

/// One line in `items` of POST /orders or POST /orders/:id/items.
class AddItem {
  const AddItem({
    this.productId,
    this.variantId,
    this.comboId,
    this.quantity = 1,
    this.seat,
    this.note,
    this.modifierOptionIds = const [],
  }) : assert(
          (productId == null) != (comboId == null),
          'Exactly one of productId or comboId',
        );

  final String? productId;
  final String? variantId;
  final String? comboId;
  final int quantity;
  final int? seat;
  final String? note;
  final List<String> modifierOptionIds;

  Map<String, dynamic> toJson() => {
        if (productId != null) 'productId': productId,
        if (variantId != null) 'variantId': variantId,
        if (comboId != null) 'comboId': comboId,
        'quantity': quantity,
        if (seat != null) 'seat': seat,
        if (note != null && note!.trim().isNotEmpty) 'note': note,
        'modifierOptionIds': modifierOptionIds,
      };

  factory AddItem.fromJson(Map<String, dynamic> j) => AddItem(
        productId: readStringOrNull(j, 'productId'),
        variantId: readStringOrNull(j, 'variantId'),
        comboId: readStringOrNull(j, 'comboId'),
        quantity: readInt(j, 'quantity', 1),
        seat: readIntOrNull(j, 'seat'),
        note: readStringOrNull(j, 'note'),
        modifierOptionIds: asStrings(j['modifierOptionIds']),
      );
}

/// Body of POST /orders. Also what the offline queue stores.
class CreateOrder {
  const CreateOrder({
    required this.type,
    this.tableId,
    this.covers,
    this.waiterId,
    this.note,
    this.offlineId,
    this.items = const [],
  });

  final String type;
  final String? tableId;
  final int? covers;
  final String? waiterId;
  final String? note;
  final String? offlineId;
  final List<AddItem> items;

  CreateOrder withOfflineId(String id) => CreateOrder(
        type: type,
        tableId: tableId,
        covers: covers,
        waiterId: waiterId,
        note: note,
        offlineId: id,
        items: items,
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        if (tableId != null) 'tableId': tableId,
        if (covers != null) 'covers': covers,
        if (waiterId != null) 'waiterId': waiterId,
        if (note != null && note!.trim().isNotEmpty) 'note': note,
        if (offlineId != null) 'offlineId': offlineId,
        if (items.isNotEmpty) 'items': [for (final i in items) i.toJson()],
      };

  factory CreateOrder.fromJson(Map<String, dynamic> j) => CreateOrder(
        type: readString(j, 'type', OrderTypes.takeaway),
        tableId: readStringOrNull(j, 'tableId'),
        covers: readIntOrNull(j, 'covers'),
        waiterId: readStringOrNull(j, 'waiterId'),
        note: readStringOrNull(j, 'note'),
        offlineId: readStringOrNull(j, 'offlineId'),
        items: [for (final i in asMaps(j['items'])) AddItem.fromJson(i)],
      );
}

/// Body of POST /orders/:id/discounts.
class DiscountInput {
  const DiscountInput({
    required this.type,
    required this.value,
    this.itemIds = const [],
    required this.reason,
    this.approvalId,
  });

  /// `PERCENT` or `FLAT`.
  final String type;

  /// Two-decimal string.
  final String value;
  final List<String> itemIds;
  final String reason;
  final String? approvalId;

  Map<String, dynamic> toJson() => {
        'type': type,
        'value': value,
        'itemIds': itemIds,
        'reason': reason,
        if (approvalId != null) 'approvalId': approvalId,
      };

  /// The payload stored on the approval (PLAN 1.2, Approval.payload).
  Map<String, dynamic> toApprovalPayload() => {
        'type': type,
        'value': value,
        'itemIds': itemIds,
        'reason': reason,
      };
}

/// One row in `payments` of POST /orders/:id/payments.
class PaymentInput {
  const PaymentInput({
    required this.method,
    required this.amount,
    this.tendered,
    this.reference,
    this.seat,
  });

  final String method;
  final String amount;
  final String? tendered;
  final String? reference;
  final int? seat;

  Map<String, dynamic> toJson() => {
        'method': method,
        'amount': amount,
        if (tendered != null) 'tendered': tendered,
        if (reference != null && reference!.trim().isNotEmpty) 'reference': reference,
        if (seat != null) 'seat': seat,
      };
}

/// Body of POST /orders/:id/payments.
class PaymentRequest {
  const PaymentRequest({required this.payments, this.tipAmount, this.completeSeat});

  final List<PaymentInput> payments;
  final String? tipAmount;
  final int? completeSeat;

  Map<String, dynamic> toJson() => {
        'payments': [for (final p in payments) p.toJson()],
        if (tipAmount != null) 'tipAmount': tipAmount,
        if (completeSeat != null) 'completeSeat': completeSeat,
      };
}

/// Body of POST /approvals.
class ApprovalRequest {
  const ApprovalRequest({
    required this.type,
    this.orderId,
    required this.payload,
    required this.reason,
  });

  final String type;
  final String? orderId;
  final Map<String, dynamic> payload;
  final String reason;

  Map<String, dynamic> toJson() => {
        'type': type,
        if (orderId != null) 'orderId': orderId,
        'payload': payload,
        'reason': reason,
      };
}

/// Body of POST /approvals/pin.
class PinApprovalRequest {
  const PinApprovalRequest({
    required this.type,
    this.orderId,
    required this.payload,
    required this.reason,
    required this.managerUserId,
    required this.pin,
  });

  final String type;
  final String? orderId;
  final Map<String, dynamic> payload;
  final String reason;
  final String managerUserId;
  final String pin;

  Map<String, dynamic> toJson() => {
        'type': type,
        if (orderId != null) 'orderId': orderId,
        'payload': payload,
        'reason': reason,
        'managerUserId': managerUserId,
        'pin': pin,
      };
}

// --- responses that wrap an order -------------------------------------------

class TicketRef {
  const TicketRef({required this.id, required this.kind, required this.station, required this.seq});

  final String id;
  final String kind;
  final String station;
  final int seq;

  factory TicketRef.fromJson(Map<String, dynamic> j) => TicketRef(
        id: readString(j, 'id'),
        kind: readString(j, 'kind'),
        station: readString(j, 'station'),
        seq: readInt(j, 'seq'),
      );
}

/// Response of POST /orders/:id/send.
class SendResult {
  const SendResult({required this.order, this.tickets = const []});

  final OrderView order;
  final List<TicketRef> tickets;

  factory SendResult.fromJson(Map<String, dynamic> j) => SendResult(
        order: OrderView.fromJson(asMap(j['order'])),
        tickets: [for (final t in asMaps(j['tickets'])) TicketRef.fromJson(t)],
      );
}

/// Response of POST /orders/:id/payments.
class PayResult {
  const PayResult({required this.order, required this.change});

  final OrderView order;
  final String change;

  num get changeValue => moneyValue(change);

  factory PayResult.fromJson(Map<String, dynamic> j) => PayResult(
        order: OrderView.fromJson(asMap(j['order'])),
        change: readMoney(j, 'change'),
      );
}

/// One share from GET /orders/:id/split.
class SplitShare {
  const SplitShare({
    required this.label,
    this.seat,
    this.itemIds = const [],
    required this.amount,
    required this.paid,
    required this.due,
  });

  final String label;
  final int? seat;
  final List<String> itemIds;

  /// Share total, two decimals.
  final String amount;
  final String paid;
  final String due;

  num get amountValue => moneyValue(amount);
  num get paidValue => moneyValue(paid);
  num get dueValue => moneyValue(due);

  /// True when nothing is left to pay on this share.
  bool get isSettled => dueValue <= 0;

  factory SplitShare.fromJson(Map<String, dynamic> j) => SplitShare(
        label: readString(j, 'label'),
        seat: readIntOrNull(j, 'seat'),
        itemIds: asStrings(j['itemIds']),
        amount: readMoney(j, 'amount'),
        paid: readMoney(j, 'paid'),
        due: readMoney(j, 'due'),
      );
}

class SplitResult {
  const SplitResult({this.shares = const []});

  final List<SplitShare> shares;

  factory SplitResult.fromJson(Map<String, dynamic> j) =>
      SplitResult(shares: [for (final s in asMaps(j['shares'])) SplitShare.fromJson(s)]);
}

// --- tables (GET /tables live view) -----------------------------------------

class TableOrderSummary {
  const TableOrderSummary({
    required this.id,
    required this.orderNumber,
    required this.covers,
    required this.grandTotal,
    this.openedAt,
    this.waiterName,
  });

  final String id;
  final String orderNumber;
  final int covers;
  final String grandTotal;
  final DateTime? openedAt;
  final String? waiterName;

  factory TableOrderSummary.fromJson(Map<String, dynamic> j) => TableOrderSummary(
        id: readString(j, 'id'),
        orderNumber: readString(j, 'orderNumber'),
        covers: readInt(j, 'covers', 1),
        grandTotal: readMoney(j, 'grandTotal'),
        openedAt: readDate(j, 'openedAt'),
        waiterName: readStringOrNull(j, 'waiterName'),
      );
}

class TableView {
  const TableView({
    required this.id,
    required this.name,
    required this.areaId,
    required this.seats,
    required this.shape,
    this.posX = 0,
    this.posY = 0,
    required this.status,
    this.mergedIntoId,
    this.order,
  });

  final String id;
  final String name;
  final String areaId;
  final int seats;

  /// `SQUARE`, `ROUND` or `LONG`.
  final String shape;
  final int posX;
  final int posY;

  /// One of `FREE`, `OCCUPIED`, `BILL_PRINTED`, `CLEANING`, `RESERVED`.
  final String status;
  final String? mergedIntoId;
  final TableOrderSummary? order;

  bool get isFree => status == 'FREE' || status == 'RESERVED';

  /// True when [covers] guests fit at this table.
  bool fits(int covers) => seats >= covers;

  factory TableView.fromJson(Map<String, dynamic> j) {
    final order = j['order'];
    return TableView(
      id: readString(j, 'id'),
      name: readString(j, 'name'),
      areaId: readString(j, 'areaId'),
      seats: readInt(j, 'seats', 4),
      shape: readString(j, 'shape', 'SQUARE'),
      posX: readInt(j, 'posX'),
      posY: readInt(j, 'posY'),
      status: readString(j, 'status', 'FREE'),
      mergedIntoId: readStringOrNull(j, 'mergedIntoId'),
      order: order is Map ? TableOrderSummary.fromJson(asMap(order)) : null,
    );
  }
}

// --- approvals ---------------------------------------------------------------

class ApprovalView {
  const ApprovalView({
    required this.id,
    required this.type,
    required this.status,
    this.orderId,
    this.payload = const {},
    required this.reason,
    this.requestedById,
    this.approverId,
    this.createdAt,
    this.decidedAt,
    this.expiresAt,
  });

  final String id;

  /// One of [ApprovalTypes].
  final String type;

  /// One of [ApprovalStatuses].
  final String status;
  final String? orderId;
  final Map<String, dynamic> payload;
  final String reason;
  final String? requestedById;
  final String? approverId;
  final DateTime? createdAt;
  final DateTime? decidedAt;
  final DateTime? expiresAt;

  bool get isPending => status == ApprovalStatuses.pending;
  bool get isApproved => status == ApprovalStatuses.approved;
  bool get isFinal => !isPending;

  factory ApprovalView.fromJson(Map<String, dynamic> j) => ApprovalView(
        id: readString(j, 'id'),
        type: readString(j, 'type'),
        status: readString(j, 'status', ApprovalStatuses.pending),
        orderId: readStringOrNull(j, 'orderId'),
        payload: asMap(j['payload']),
        reason: readString(j, 'reason'),
        requestedById: readStringOrNull(j, 'requestedById'),
        approverId: readStringOrNull(j, 'approverId'),
        createdAt: readDate(j, 'createdAt'),
        decidedAt: readDate(j, 'decidedAt'),
        expiresAt: readDate(j, 'expiresAt'),
      );
}

// --- day close totals (PLAN 1.6) ---------------------------------------------

/// `{ count, amount }` rows used in `byPayment`, `byType`, `voids`, `refunds`.
class CountAmount {
  const CountAmount({this.key = '', this.count = 0, this.amount = '0.00'});

  final String key;
  final int count;
  final String amount;

  num get amountValue => moneyValue(amount);

  factory CountAmount.fromJson(Map<String, dynamic> j, {String keyField = ''}) {
    final key = keyField.isEmpty ? '' : readString(j, keyField);
    return CountAmount(key: key, count: readInt(j, 'count'), amount: readMoney(j, 'amount'));
  }
}

class CategoryTotal {
  const CategoryTotal({
    required this.categoryId,
    required this.name,
    required this.quantity,
    required this.amount,
  });

  final String categoryId;
  final String name;
  final int quantity;
  final String amount;

  num get amountValue => moneyValue(amount);

  factory CategoryTotal.fromJson(Map<String, dynamic> j) => CategoryTotal(
        categoryId: readString(j, 'categoryId'),
        name: readString(j, 'name'),
        quantity: readInt(j, 'quantity'),
        amount: readMoney(j, 'amount'),
      );
}

class StaffDiscount {
  const StaffDiscount({required this.userId, required this.name, required this.amount});

  final String userId;
  final String name;
  final String amount;

  factory StaffDiscount.fromJson(Map<String, dynamic> j) => StaffDiscount(
        userId: readString(j, 'userId'),
        name: readString(j, 'name'),
        amount: readMoney(j, 'amount'),
      );
}

/// Totals shape from PLAN 1.6, returned by `GET /reports/x` and inside each
/// day close from `POST /reports/z`.
class DayCloseTotals {
  const DayCloseTotals({
    required this.businessDate,
    this.ordersCount = 0,
    this.ordersPaid = 0,
    this.ordersVoid = 0,
    this.ordersOpen = 0,
    this.gross = '0.00',
    this.discounts = '0.00',
    this.serviceCharge = '0.00',
    this.tax = const [],
    this.roundOff = '0.00',
    this.net = '0.00',
    this.tips = '0.00',
    this.byPayment = const [],
    this.byType = const [],
    this.byCategory = const [],
    this.voids = const CountAmount(),
    this.refunds = const CountAmount(),
    this.discountsByStaff = const [],
    this.cashExpected,
  });

  final String businessDate;
  final int ordersCount;
  final int ordersPaid;
  final int ordersVoid;
  final int ordersOpen;
  final String gross;
  final String discounts;
  final String serviceCharge;
  final List<TaxLine> tax;
  final String roundOff;
  final String net;
  final String tips;
  final List<CountAmount> byPayment;
  final List<CountAmount> byType;
  final List<CategoryTotal> byCategory;
  final CountAmount voids;
  final CountAmount refunds;
  final List<StaffDiscount> discountsByStaff;
  final String? cashExpected;

  num get netValue => moneyValue(net);
  num get cashExpectedValue => moneyValue(cashExpected ?? '0');

  factory DayCloseTotals.fromJson(Map<String, dynamic> j) {
    final orders = asMap(j['orders']);
    final voids = asMap(j['voids']);
    final refunds = asMap(j['refunds']);
    return DayCloseTotals(
      businessDate: readString(j, 'businessDate'),
      ordersCount: readInt(orders, 'count'),
      ordersPaid: readInt(orders, 'paid'),
      ordersVoid: readInt(orders, 'void'),
      ordersOpen: readInt(orders, 'open'),
      gross: readMoney(j, 'gross'),
      discounts: readMoney(j, 'discounts'),
      serviceCharge: readMoney(j, 'serviceCharge'),
      tax: [for (final t in asMaps(j['tax'])) TaxLine.fromJson(t)],
      roundOff: readMoney(j, 'roundOff'),
      net: readMoney(j, 'net'),
      tips: readMoney(j, 'tips'),
      byPayment: [for (final p in asMaps(j['byPayment'])) CountAmount.fromJson(p, keyField: 'method')],
      byType: [for (final t in asMaps(j['byType'])) CountAmount.fromJson(t, keyField: 'type')],
      byCategory: [for (final c in asMaps(j['byCategory'])) CategoryTotal.fromJson(c)],
      voids: CountAmount.fromJson(voids),
      refunds: CountAmount.fromJson(refunds),
      discountsByStaff: [for (final s in asMaps(j['discountsByStaff'])) StaffDiscount.fromJson(s)],
      cashExpected: readMoneyOrNull(j, 'cashExpected'),
    );
  }
}
