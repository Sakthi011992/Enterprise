/// Kitchen display and ready-list models (PLAN 1.7 "KDS").
library;

import '../../pos/data/pos_models.dart';

/// Wire values for `KdsStatus`.
abstract final class KdsStatuses {
  static const newTicket = 'NEW';
  static const preparing = 'PREPARING';
  static const ready = 'READY';
  static const served = 'SERVED';
}

/// The order a ticket belongs to, as the display shows it.
class KdsOrderRef {
  const KdsOrderRef({
    required this.id,
    required this.orderNumber,
    required this.type,
    this.tableName,
    this.tabNumber,
    this.waiterName,
    this.covers = 1,
    this.source,
    this.guestName,
  });

  final String id;
  final String orderNumber;
  final String type;
  final String? tableName;
  final String? tabNumber;
  final String? waiterName;
  final int covers;

  /// `POS`, `KIOSK` or `GUEST_QR` (Phase 4). Null on older servers.
  final String? source;

  /// Guest name on a QR order, when the server sends one.
  final String? guestName;

  bool get isGuestQr => source == 'GUEST_QR';

  /// "R4", "Tab T-08", "Bar seat 7", or the order type when there is no place.
  String get placeLabel {
    final table = tableName;
    if (table != null && table.isNotEmpty) return table;
    final tab = tabNumber;
    if (tab != null && tab.isNotEmpty) return 'Tab $tab';
    return OrderTypes.label(type);
  }

  factory KdsOrderRef.fromJson(Map<String, dynamic> j) => KdsOrderRef(
        id: readString(j, 'id'),
        orderNumber: readString(j, 'orderNumber'),
        type: readString(j, 'type', OrderTypes.takeaway),
        tableName: readStringOrNull(j, 'tableName'),
        tabNumber: readStringOrNull(j, 'tabNumber'),
        waiterName: readStringOrNull(j, 'waiterName'),
        covers: readInt(j, 'covers', 1),
        source: readStringOrNull(j, 'source'),
        guestName: readStringOrNull(j, 'guestName'),
      );
}

/// One line on a ticket. [voided] lines are shown struck through.
class KdsItem {
  const KdsItem({
    required this.orderItemId,
    required this.name,
    this.variantName,
    this.quantity = 1,
    this.modifiers = const [],
    this.note,
    this.seat,
    this.guestName,
    this.voided = false,
  });

  final String orderItemId;
  final String name;
  final String? variantName;
  final int quantity;
  final List<String> modifiers;
  final String? note;
  final int? seat;
  final bool voided;

  /// Guest who ordered the line on a QR order (Phase 4), or null.
  final String? guestName;

  /// "2 × Classic Mojito", the form the display uses.
  String get headline {
    final variant = variantName;
    final base = variant == null || variant.isEmpty ? name : '$name $variant';
    return '$quantity × $base';
  }

  factory KdsItem.fromJson(Map<String, dynamic> j) => KdsItem(
        orderItemId: readString(j, 'orderItemId'),
        name: readString(j, 'name'),
        variantName: readStringOrNull(j, 'variantName'),
        quantity: readInt(j, 'quantity', 1),
        modifiers: asStrings(j['modifiers']),
        note: readStringOrNull(j, 'note'),
        seat: readIntOrNull(j, 'seat'),
        voided: readBool(j, 'voided'),
        guestName: readStringOrNull(j, 'guestName'),
      );
}

/// `KdsTicket` from PLAN 1.7. Times are instants; the screen corrects the
/// device clock with [KdsBoard.clockOffset].
class KdsTicket {
  const KdsTicket({
    required this.id,
    required this.kind,
    required this.station,
    required this.seq,
    required this.label,
    required this.kdsStatus,
    required this.order,
    this.items = const [],
    this.createdAt,
    this.startedAt,
    this.readyAt,
    this.servedAt,
    this.ageSeconds = 0,
    this.colour = 'green',
  });

  final String id;

  /// `KOT` or `BOT`.
  final String kind;
  final String station;
  final int seq;

  /// `${kind} ${seq}`, e.g. "BOT 12".
  final String label;

  /// One of [KdsStatuses].
  final String kdsStatus;
  final KdsOrderRef order;
  final List<KdsItem> items;
  final DateTime? createdAt;
  final DateTime? startedAt;
  final DateTime? readyAt;
  final DateTime? servedAt;
  final int ageSeconds;

  /// Server colour: `green`, `amber` or `red`.
  final String colour;

  bool get isNew => kdsStatus == KdsStatuses.newTicket;
  bool get isPreparing => kdsStatus == KdsStatuses.preparing;
  bool get isReady => kdsStatus == KdsStatuses.ready;
  bool get isServed => kdsStatus == KdsStatuses.served;

  /// Items that are still live (not voided).
  List<KdsItem> get liveItems => [for (final i in items) if (!i.voided) i];

  factory KdsTicket.fromJson(Map<String, dynamic> j) => KdsTicket(
        id: readString(j, 'id'),
        kind: readString(j, 'kind', 'KOT'),
        station: readString(j, 'station'),
        seq: readInt(j, 'seq'),
        label: readString(j, 'label'),
        kdsStatus: readString(j, 'kdsStatus', KdsStatuses.newTicket),
        order: KdsOrderRef.fromJson(asMap(j['order'])),
        items: [for (final i in asMaps(j['items'])) KdsItem.fromJson(i)],
        createdAt: readDate(j, 'createdAt'),
        startedAt: readDate(j, 'startedAt'),
        readyAt: readDate(j, 'readyAt'),
        servedAt: readDate(j, 'servedAt'),
        ageSeconds: readInt(j, 'ageSeconds'),
        colour: readString(j, 'colour', 'green'),
      );
}

/// One line on the all-day panel.
class KdsAllDayRow {
  const KdsAllDayRow({required this.name, this.variantName, required this.quantity});

  final String name;
  final String? variantName;
  final int quantity;

  factory KdsAllDayRow.fromJson(Map<String, dynamic> j) => KdsAllDayRow(
        name: readString(j, 'name'),
        variantName: readStringOrNull(j, 'variantName'),
        quantity: readInt(j, 'quantity'),
      );
}

/// `GET /kds/tickets` response. [receivedAt] is the device time when the
/// response arrived, so [clockOffset] can turn device time into server time.
class KdsBoard {
  const KdsBoard({
    required this.serverTime,
    required this.receivedAt,
    this.tickets = const [],
    this.allDay = const [],
    this.avgTicketSeconds = 0,
  });

  final DateTime serverTime;
  final DateTime receivedAt;
  final List<KdsTicket> tickets;
  final List<KdsAllDayRow> allDay;
  final int avgTicketSeconds;

  /// Add to device time to get server time.
  Duration get clockOffset => serverTime.difference(receivedAt);

  List<KdsTicket> withStatus(String status) => [
        for (final t in tickets)
          if (t.kdsStatus == status) t,
      ];

  factory KdsBoard.fromJson(Map<String, dynamic> j, {DateTime? receivedAt}) {
    final now = receivedAt ?? DateTime.now();
    return KdsBoard(
      serverTime: readDate(j, 'serverTime') ?? now,
      receivedAt: now,
      tickets: [for (final t in asMaps(j['tickets'])) KdsTicket.fromJson(t)],
      allDay: [for (final r in asMaps(j['allDay'])) KdsAllDayRow.fromJson(r)],
      avgTicketSeconds: readInt(j, 'avgTicketSeconds'),
    );
  }
}

/// One line on a ready-to-serve card.
class ReadyLine {
  const ReadyLine({required this.name, this.variantName, this.quantity = 1, this.seat});

  final String name;
  final String? variantName;
  final int quantity;
  final int? seat;

  factory ReadyLine.fromJson(Map<String, dynamic> j) => ReadyLine(
        name: readString(j, 'name'),
        variantName: readStringOrNull(j, 'variantName'),
        quantity: readInt(j, 'quantity', 1),
        seat: readIntOrNull(j, 'seat'),
      );
}

/// `ReadyItem` from PLAN 1.7: a READY ticket waiting for the waiter.
class ReadyItem {
  const ReadyItem({
    required this.ticketId,
    required this.label,
    required this.station,
    this.tableName,
    this.tabNumber,
    this.items = const [],
    this.readyAt,
    this.waitingSeconds = 0,
    this.overdue = false,
  });

  final String ticketId;
  final String label;
  final String station;
  final String? tableName;
  final String? tabNumber;
  final List<ReadyLine> items;
  final DateTime? readyAt;
  final int waitingSeconds;
  final bool overdue;

  /// "R4", "Tab T-08" or the label when neither is known.
  String get placeLabel {
    final table = tableName;
    if (table != null && table.isNotEmpty) return table;
    final tab = tabNumber;
    if (tab != null && tab.isNotEmpty) return 'Tab $tab';
    return label;
  }

  factory ReadyItem.fromJson(Map<String, dynamic> j) => ReadyItem(
        ticketId: readString(j, 'ticketId'),
        label: readString(j, 'label'),
        station: readString(j, 'station'),
        tableName: readStringOrNull(j, 'tableName'),
        tabNumber: readStringOrNull(j, 'tabNumber'),
        items: [for (final i in asMaps(j['items'])) ReadyLine.fromJson(i)],
        readyAt: readDate(j, 'readyAt'),
        waitingSeconds: readInt(j, 'waitingSeconds'),
        overdue: readBool(j, 'overdue'),
      );
}

/// `GET /kds/stations` row.
class KdsStation {
  const KdsStation({required this.station, required this.label, this.activeCount = 0});

  final String station;
  final String label;
  final int activeCount;

  factory KdsStation.fromJson(Map<String, dynamic> j) => KdsStation(
        station: readString(j, 'station'),
        label: readString(j, 'label', readString(j, 'station')),
        activeCount: readInt(j, 'activeCount'),
      );
}
