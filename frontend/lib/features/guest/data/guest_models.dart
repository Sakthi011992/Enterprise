/// Guest QR ordering models (PLAN 2.3–2.5). Every `fromJson` is tolerant of
/// missing optional keys and of money sent as a number instead of a string,
/// using the same JSON helpers as the POS models.
library;

import '../../pos/data/pos_models.dart'
    show PosModifierGroup, asMap, asMaps, asStrings, moneyText, moneyValue, readBool, readInt, readString, readStringOrNull;

export '../../pos/data/pos_models.dart' show PosModifierGroup, PosModifierOption;

double _money(Object? v) => moneyValue(moneyText(v)).toDouble();

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

// --- 2.3 table lookup, start, verify -----------------------------------------

enum GuestRouting { direct, waiter }

enum GuestVerifyMethod { staticOtp, tablePin, smsOtp }

GuestRouting parseRouting(Object? v) =>
    v?.toString().toUpperCase() == 'DIRECT' ? GuestRouting.direct : GuestRouting.waiter;

GuestVerifyMethod parseMethod(Object? v) => switch (v?.toString().toUpperCase()) {
      'TABLE_PIN' => GuestVerifyMethod.tablePin,
      'SMS_OTP' => GuestVerifyMethod.smsOtp,
      _ => GuestVerifyMethod.staticOtp,
    };

String methodWire(GuestVerifyMethod m) => switch (m) {
      GuestVerifyMethod.staticOtp => 'STATIC_OTP',
      GuestVerifyMethod.tablePin => 'TABLE_PIN',
      GuestVerifyMethod.smsOtp => 'SMS_OTP',
    };

/// Safe subset of the guest configuration returned with the table lookup.
class GuestSettings {
  const GuestSettings({
    this.routing = GuestRouting.waiter,
    this.method = GuestVerifyMethod.staticOtp,
    this.codeLength = 6,
    this.ageGate = true,
    this.minAge = 25,
    this.allowGuestCancel = true,
  });

  final GuestRouting routing;
  final GuestVerifyMethod method;
  final int codeLength;
  final bool ageGate;
  final int minAge;
  final bool allowGuestCancel;

  factory GuestSettings.fromJson(Map<String, dynamic> j) {
    final verification = asMap(j['verification']);
    final method = parseMethod(verification['method'] ?? j['method']);
    final fallbackLength = method == GuestVerifyMethod.tablePin ? 4 : 6;
    return GuestSettings(
      routing: parseRouting(j['routing']),
      method: method,
      codeLength: readInt(verification, 'codeLength', readInt(j, 'codeLength', fallbackLength)),
      ageGate: readBool(j, 'ageGate', true),
      minAge: readInt(j, 'minAge', 25),
      allowGuestCancel: readBool(j, 'allowGuestCancel', true),
    );
  }
}

/// GET /guest/t/:qrToken
class GuestTableInfo {
  const GuestTableInfo({
    required this.tableId,
    required this.tableName,
    this.areaName,
    required this.outletName,
    this.logoUrl,
    this.themeId,
    this.settings = const GuestSettings(),
    this.seated = true,
    this.sessionOpen = false,
  });

  final String tableId;
  final String tableName;
  final String? areaName;
  final String outletName;
  final String? logoUrl;
  final String? themeId;
  final GuestSettings settings;
  final bool seated;
  final bool sessionOpen;

  /// "Table R4 · Rooftop"
  String get tableLine => areaName == null || areaName!.isEmpty
      ? 'Table $tableName'
      : 'Table $tableName · $areaName';

  factory GuestTableInfo.fromJson(Map<String, dynamic> j) {
    final table = j['table'];
    final tableMap = asMap(table);
    final outlet = j['outlet'];
    final outletMap = asMap(outlet);
    final area = tableMap['area'];
    return GuestTableInfo(
      tableId: readString(tableMap, 'id', readString(j, 'tableId')),
      tableName: table is String
          ? table
          : readString(tableMap, 'name', readString(tableMap, 'label', readString(j, 'tableName'))),
      areaName: area is String
          ? area
          : readStringOrNull(asMap(area), 'name') ?? readStringOrNull(tableMap, 'areaName'),
      outletName: outlet is String
          ? outlet
          : readString(outletMap, 'name', readString(j, 'outletName', 'Welcome')),
      logoUrl: readStringOrNull(outletMap, 'logoUrl') ?? readStringOrNull(j, 'logoUrl'),
      themeId: readStringOrNull(j, 'themeId'),
      settings: GuestSettings.fromJson(asMap(j['settings'])),
      seated: readBool(j, 'seated', true),
      sessionOpen: readBool(j, 'sessionOpen'),
    );
  }
}

/// POST /guest/t/:qrToken/start
class GuestStart {
  const GuestStart({required this.verificationId, required this.method, required this.codeLength});

  final String verificationId;
  final GuestVerifyMethod method;
  final int codeLength;

  factory GuestStart.fromJson(Map<String, dynamic> j) {
    final method = parseMethod(j['method']);
    return GuestStart(
      verificationId: readString(j, 'verificationId'),
      method: method,
      codeLength: readInt(j, 'codeLength', method == GuestVerifyMethod.tablePin ? 4 : 6),
    );
  }
}

class GuestParticipant {
  const GuestParticipant({required this.id, required this.name});

  final String id;
  final String name;

  factory GuestParticipant.fromJson(Map<String, dynamic> j) =>
      GuestParticipant(id: readString(j, 'id'), name: readString(j, 'name'));

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

/// POST /guest/t/:qrToken/verify
class GuestJoin {
  const GuestJoin({
    required this.guestToken,
    required this.sessionId,
    required this.participant,
    this.ageConfirmed = false,
  });

  final String guestToken;
  final String sessionId;
  final GuestParticipant participant;
  final bool ageConfirmed;

  factory GuestJoin.fromJson(Map<String, dynamic> j) {
    final session = asMap(j['session']);
    return GuestJoin(
      guestToken: readString(j, 'guestToken'),
      sessionId: readString(session, 'id'),
      participant: GuestParticipant.fromJson(asMap(j['participant'])),
      ageConfirmed: session['ageConfirmedAt'] != null,
    );
  }
}

// --- 2.4 menu -----------------------------------------------------------------

class GuestVariant {
  const GuestVariant({required this.id, required this.name, required this.price, this.basePrice});

  final String id;
  final String name;
  final double price;
  final double? basePrice;

  factory GuestVariant.fromJson(Map<String, dynamic> j) => GuestVariant(
        id: readString(j, 'id'),
        name: readString(j, 'name'),
        price: _money(j['price']),
        basePrice: j['basePrice'] == null ? null : _money(j['basePrice']),
      );
}

class GuestProduct {
  const GuestProduct({
    required this.id,
    required this.name,
    required this.categoryId,
    this.description = '',
    required this.price,
    this.basePrice,
    this.available = true,
    this.isAlcohol = false,
    this.featured = false,
    this.imageUrl,
    this.variants = const [],
    this.modifierGroups = const [],
  });

  final String id;
  final String name;
  final String categoryId;
  final String description;

  /// Current price (happy hour and area markup applied).
  final double price;

  /// Price before happy hour, shown struck through when higher than [price].
  final double? basePrice;
  final bool available;
  final bool isAlcohol;
  final bool featured;
  final String? imageUrl;
  final List<GuestVariant> variants;
  final List<PosModifierGroup> modifierGroups;

  bool get discounted => basePrice != null && basePrice! > price;

  /// Opens the choices sheet instead of adding straight away.
  bool get hasChoices => modifierGroups.isNotEmpty || variants.length > 1;

  factory GuestProduct.fromJson(Map<String, dynamic> j, String categoryId) {
    final variants = [for (final v in asMaps(j['variants'])) GuestVariant.fromJson(v)];
    final first = variants.isEmpty ? null : variants.first;
    return GuestProduct(
      id: readString(j, 'id'),
      name: readString(j, 'name'),
      categoryId: readString(j, 'categoryId', categoryId),
      description: readString(j, 'description'),
      price: j['price'] == null ? (first?.price ?? 0) : _money(j['price']),
      basePrice: j['basePrice'] == null ? first?.basePrice : _money(j['basePrice']),
      available: readBool(j, 'available', true),
      isAlcohol: readBool(j, 'isAlcohol'),
      featured: readBool(j, 'featured') || readBool(j, 'popular'),
      imageUrl: readStringOrNull(j, 'imageUrl'),
      variants: variants,
      modifierGroups: [
        for (final g in asMaps(j['modifierGroups'])) PosModifierGroup.fromJson(g),
      ],
    );
  }
}

class GuestCategory {
  const GuestCategory({required this.id, required this.name, this.products = const []});

  final String id;
  final String name;
  final List<GuestProduct> products;

  factory GuestCategory.fromJson(Map<String, dynamic> j) {
    final id = readString(j, 'id');
    return GuestCategory(
      id: id,
      name: readString(j, 'name'),
      products: [for (final p in asMaps(j['products'])) GuestProduct.fromJson(p, id)],
    );
  }
}

/// "Happy hour 30% off cocktails until 8 pm"
class GuestHappyHour {
  const GuestHappyHour({required this.label, this.until});

  final String label;
  final String? until;

  factory GuestHappyHour.fromJson(Map<String, dynamic> j) =>
      GuestHappyHour(label: readString(j, 'label'), until: readStringOrNull(j, 'until'));
}

/// GET /guest/menu
class GuestMenu {
  const GuestMenu({this.categories = const [], this.happyHour});

  final List<GuestCategory> categories;
  final GuestHappyHour? happyHour;

  Iterable<GuestProduct> get products => categories.expand((c) => c.products);

  List<GuestProduct> get popular => products.where((p) => p.featured).toList();

  GuestProduct? product(String id) {
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }

  factory GuestMenu.fromJson(Object? data) {
    final j = asMap(data);
    final cats = data is List ? asMaps(data) : asMaps(j['categories']);
    final hh = j['happyHour'];
    return GuestMenu(
      categories: [for (final c in cats) GuestCategory.fromJson(c)],
      happyHour: hh is Map ? GuestHappyHour.fromJson(asMap(hh)) : null,
    );
  }
}

// --- 2.4 rounds -------------------------------------------------------------

class GuestRoundModifier {
  const GuestRoundModifier({required this.groupId, required this.optionId});

  final String groupId;
  final String optionId;

  Map<String, dynamic> toJson() => {'groupId': groupId, 'optionId': optionId};
}

/// One line of a placed round, as submitted.
class GuestRoundItem {
  const GuestRoundItem({
    required this.productId,
    this.variantId,
    required this.quantity,
    this.modifiers = const [],
    this.note,
  });

  final String productId;
  final String? variantId;
  final int quantity;
  final List<GuestRoundModifier> modifiers;
  final String? note;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        if (variantId != null) 'variantId': variantId,
        'quantity': quantity,
        'modifiers': [for (final m in modifiers) m.toJson()],
        if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
      };
}

// --- 2.5 order view --------------------------------------------------------

enum GuestLineState { waitingWaiter, sent, cooking, ready, served, cancelled }

GuestLineState parseLineState(Object? v) => switch (v?.toString().toUpperCase()) {
      'SENT' => GuestLineState.sent,
      'COOKING' => GuestLineState.cooking,
      'READY' => GuestLineState.ready,
      'SERVED' => GuestLineState.served,
      'CANCELLED' => GuestLineState.cancelled,
      _ => GuestLineState.waitingWaiter,
    };

String lineStateWire(GuestLineState s) => switch (s) {
      GuestLineState.waitingWaiter => 'WAITING_WAITER',
      GuestLineState.sent => 'SENT',
      GuestLineState.cooking => 'COOKING',
      GuestLineState.ready => 'READY',
      GuestLineState.served => 'SERVED',
      GuestLineState.cancelled => 'CANCELLED',
    };

enum GuestRoundStatus { pending, confirmed, rejected, cancelled, expired }

GuestRoundStatus parseRoundStatus(Object? v) => switch (v?.toString().toUpperCase()) {
      'CONFIRMED' => GuestRoundStatus.confirmed,
      'REJECTED' => GuestRoundStatus.rejected,
      'CANCELLED' => GuestRoundStatus.cancelled,
      'EXPIRED' => GuestRoundStatus.expired,
      _ => GuestRoundStatus.pending,
    };

String roundStatusWire(GuestRoundStatus s) => s.name.toUpperCase();

enum GuestOrderStatus { open, billed, paid, closed }

GuestOrderStatus parseOrderStatus(Object? v) => switch (v?.toString().toUpperCase()) {
      'BILLED' => GuestOrderStatus.billed,
      'PAID' => GuestOrderStatus.paid,
      'CLOSED' => GuestOrderStatus.closed,
      _ => GuestOrderStatus.open,
    };

class GuestLine {
  const GuestLine({
    required this.name,
    this.variant,
    this.modifiers = const [],
    required this.qty,
    required this.lineTotal,
    required this.state,
    this.updatedAt,
  });

  final String name;
  final String? variant;
  final List<String> modifiers;
  final int qty;
  final double lineTotal;
  final GuestLineState state;
  final DateTime? updatedAt;

  GuestLine copyWith({GuestLineState? state, DateTime? updatedAt}) => GuestLine(
        name: name,
        variant: variant,
        modifiers: modifiers,
        qty: qty,
        lineTotal: lineTotal,
        state: state ?? this.state,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  factory GuestLine.fromJson(Map<String, dynamic> j) => GuestLine(
        name: readString(j, 'name'),
        variant: readStringOrNull(j, 'variant'),
        modifiers: asStrings(j['modifiers']),
        qty: readInt(j, 'qty', readInt(j, 'quantity', 1)),
        lineTotal: _money(j['lineTotal']),
        state: parseLineState(j['state']),
        updatedAt: _date(j['updatedAt']),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'variant': variant,
        'modifiers': modifiers,
        'qty': qty,
        'lineTotal': lineTotal.toStringAsFixed(2),
        'state': lineStateWire(state),
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
      };
}

class GuestRound {
  const GuestRound({
    required this.id,
    required this.by,
    required this.status,
    this.rejectReason,
    this.lines = const [],
    this.createdAt,
    this.participantId,
    this.mine = false,
  });

  final String id;
  final String by;
  final GuestRoundStatus status;
  final String? rejectReason;
  final List<GuestLine> lines;
  final DateTime? createdAt;
  final String? participantId;

  /// True when the round was placed from this phone (asked of G-B as `mine`).
  final bool mine;

  double get total => lines.fold(0, (sum, l) => sum + l.lineTotal);

  GuestRound copyWith({
    GuestRoundStatus? status,
    String? rejectReason,
    List<GuestLine>? lines,
    bool? mine,
  }) =>
      GuestRound(
        id: id,
        by: by,
        status: status ?? this.status,
        rejectReason: rejectReason ?? this.rejectReason,
        lines: lines ?? this.lines,
        createdAt: createdAt,
        participantId: participantId,
        mine: mine ?? this.mine,
      );

  factory GuestRound.fromJson(Map<String, dynamic> j) => GuestRound(
        id: readString(j, 'id'),
        by: readString(j, 'by'),
        status: parseRoundStatus(j['status']),
        rejectReason: readStringOrNull(j, 'rejectReason'),
        lines: [for (final l in asMaps(j['lines'])) GuestLine.fromJson(l)],
        createdAt: _date(j['createdAt']),
        participantId: readStringOrNull(j, 'participantId'),
        mine: readBool(j, 'mine'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'by': by,
        'status': roundStatusWire(status),
        'rejectReason': rejectReason,
        'lines': [for (final l in lines) l.toJson()],
        'createdAt': createdAt?.toUtc().toIso8601String(),
        'participantId': participantId,
        'mine': mine,
      };
}

/// POST /guest/rounds result. Same shape as one entry of `rounds`.
typedef GuestRoundView = GuestRound;

class GuestTotals {
  const GuestTotals({
    this.subtotal = 0,
    this.discount = 0,
    this.serviceCharge = 0,
    this.tax = 0,
    this.roundOff = 0,
    this.grandTotal = 0,
    this.paid = 0,
    this.due = 0,
  });

  final double subtotal, discount, serviceCharge, tax, roundOff, grandTotal, paid, due;

  factory GuestTotals.fromJson(Map<String, dynamic> j) => GuestTotals(
        subtotal: _money(j['subtotal']),
        discount: _money(j['discount']),
        serviceCharge: _money(j['serviceCharge']),
        tax: _money(j['tax']),
        roundOff: _money(j['roundOff']),
        grandTotal: _money(j['grandTotal']),
        paid: _money(j['paid']),
        due: _money(j['due']),
      );

  Map<String, dynamic> toJson() => {
        for (final e in {
          'subtotal': subtotal,
          'discount': discount,
          'serviceCharge': serviceCharge,
          'tax': tax,
          'roundOff': roundOff,
          'grandTotal': grandTotal,
          'paid': paid,
          'due': due,
        }.entries)
          e.key: e.value.toStringAsFixed(2),
      };
}

class GuestCheckoutState {
  const GuestCheckoutState({this.mode = 'WAITER', this.requested = false});

  final String mode;
  final bool requested;

  factory GuestCheckoutState.fromJson(Map<String, dynamic> j) => GuestCheckoutState(
        mode: readString(j, 'mode', 'WAITER'),
        requested: readBool(j, 'requested'),
      );
}

/// GET /guest/order and the `guest.order.updated` payload.
class GuestOrderView {
  const GuestOrderView({
    required this.table,
    this.status = GuestOrderStatus.open,
    this.rounds = const [],
    this.totals = const GuestTotals(),
    this.checkout = const GuestCheckoutState(),
    this.atTable,
  });

  final String table;
  final GuestOrderStatus status;
  final List<GuestRound> rounds;
  final GuestTotals totals;
  final GuestCheckoutState checkout;

  /// People who joined the table session (optional, asked of G-B).
  final int? atTable;

  bool get isEnded => status == GuestOrderStatus.paid || status == GuestOrderStatus.closed;

  /// Amount of PENDING rounds, included in the totals as an estimate.
  double get pendingEstimate => rounds
      .where((r) => r.status == GuestRoundStatus.pending)
      .fold(0, (sum, r) => sum + r.total);

  /// Items that count on the bill (not cancelled).
  int get itemCount => rounds
      .expand((r) => r.lines)
      .where((l) => l.state != GuestLineState.cancelled)
      .fold(0, (sum, l) => sum + l.qty);

  factory GuestOrderView.fromJson(Map<String, dynamic> j) => GuestOrderView(
        table: readString(j, 'table'),
        status: parseOrderStatus(j['status']),
        rounds: [for (final r in asMaps(j['rounds'])) GuestRound.fromJson(r)],
        totals: GuestTotals.fromJson(asMap(j['totals'])),
        checkout: GuestCheckoutState.fromJson(asMap(j['checkout'])),
        atTable: j['atTable'] is num ? (j['atTable'] as num).toInt() : null,
      );

  Map<String, dynamic> toJson() => {
        'table': table,
        'status': status.name.toUpperCase(),
        'rounds': [for (final r in rounds) r.toJson()],
        'totals': totals.toJson(),
        'checkout': {'mode': checkout.mode, 'requested': checkout.requested},
        if (atTable != null) 'atTable': atTable,
      };
}

// --- service requests and checkout ------------------------------------------

enum GuestServiceType { callWaiter, bill }

String serviceTypeWire(GuestServiceType t) =>
    t == GuestServiceType.bill ? 'BILL' : 'CALL_WAITER';

class GuestServiceRequest {
  const GuestServiceRequest({required this.id, required this.type, this.status = 'OPEN'});

  final String id;
  final String type;
  final String status;

  factory GuestServiceRequest.fromJson(Map<String, dynamic> j) => GuestServiceRequest(
        id: readString(j, 'id'),
        type: readString(j, 'type'),
        status: readString(j, 'status', 'OPEN'),
      );
}

/// POST /guest/checkout result.
class GuestCheckout {
  const GuestCheckout({required this.mode, this.requestId});

  final String mode;
  final String? requestId;

  factory GuestCheckout.fromJson(Map<String, dynamic> j) =>
      GuestCheckout(mode: readString(j, 'mode', 'WAITER'), requestId: readStringOrNull(j, 'requestId'));
}

/// Realtime messages for the guest (PLAN 2.6).
sealed class GuestLiveEvent {
  const GuestLiveEvent();
}

class GuestOrderUpdated extends GuestLiveEvent {
  const GuestOrderUpdated(this.view);
  final GuestOrderView view;
}

class GuestSessionClosed extends GuestLiveEvent {
  const GuestSessionClosed();
}
