/// Bar tab and bottle locker models (PLAN 1.7 "Bar tabs and bottle locker").
/// Money stays in its wire form (two-decimal string). Use the `...Value`
/// getters for display maths only. The server totals are the ones shown.
library;

import '../../pos/data/pos_models.dart';
import '../../pos/presentation/pos_format.dart';

/// Wire values for `TabStatus`.
abstract final class TabStatuses {
  static const open = 'OPEN';
  static const closed = 'CLOSED';
  static const voided = 'VOID';
}

/// Wire values for `TabSecurity`.
abstract final class TabSecurities {
  static const cardPreauth = 'CARD_PREAUTH';
  static const cashDeposit = 'CASH_DEPOSIT';
  static const houseAccount = 'HOUSE_ACCOUNT';
  static const none = 'NONE';
}

/// Wire values for `TabLinkType`.
abstract final class TabLinkTypes {
  static const barSeat = 'BAR_SEAT';
  static const table = 'TABLE';
  static const queueToken = 'QUEUE_TOKEN';
  static const none = 'NONE';
}

/// Wire values for `LockerStatus`.
abstract final class LockerStatuses {
  static const active = 'ACTIVE';
  static const finished = 'FINISHED';
  static const expired = 'EXPIRED';
  static const removed = 'REMOVED';
}

/// Wire values for `LockerEventKind`.
abstract final class LockerEventKinds {
  static const store = 'STORE';
  static const serve = 'SERVE';
  static const adjust = 'ADJUST';
  static const remove = 'REMOVE';
}

/// Person reference inside a tab (`openedBy`).
class TabPerson {
  const TabPerson({required this.id, required this.name});

  final String id;
  final String name;

  factory TabPerson.fromJson(Map<String, dynamic> j) =>
      TabPerson(id: readString(j, 'id'), name: readString(j, 'name'));
}

/// `TabView` from PLAN 1.7. `order` is present only on `GET /tabs/:id`.
class TabView {
  const TabView({
    required this.id,
    required this.number,
    required this.guestName,
    this.mobile,
    this.ageChecked = false,
    required this.security,
    this.cardLast4,
    this.amountHeld = '0.00',
    this.houseAccount,
    required this.tabLimit,
    this.warnAtPercent = 80,
    required this.spent,
    required this.remaining,
    this.percentUsed = 0,
    this.nearLimit = false,
    this.linkType = TabLinkTypes.none,
    this.linkLabel,
    this.table,
    required this.status,
    this.openedAt,
    this.closedAt,
    this.openedBy,
    required this.orderId,
    this.orderStatus,
    this.itemCount = 0,
    this.order,
  });

  final String id;
  final String number;
  final String guestName;
  final String? mobile;
  final bool ageChecked;

  /// One of [TabSecurities].
  final String security;
  final String? cardLast4;
  final String amountHeld;
  final String? houseAccount;
  final String tabLimit;
  final int warnAtPercent;
  final String spent;
  final String remaining;
  final num percentUsed;
  final bool nearLimit;

  /// One of [TabLinkTypes].
  final String linkType;
  final String? linkLabel;
  final TableRef? table;

  /// One of [TabStatuses].
  final String status;
  final DateTime? openedAt;
  final DateTime? closedAt;
  final TabPerson? openedBy;
  final String orderId;
  final String? orderStatus;
  final int itemCount;
  final OrderView? order;

  bool get isOpen => status == TabStatuses.open;
  bool get isClosed => status == TabStatuses.closed;
  num get spentValue => moneyValue(spent);
  num get tabLimitValue => moneyValue(tabLimit);
  num get amountHeldValue => moneyValue(amountHeld);

  /// Short label for the security column: "Card ••4821", "Deposit ₹2,000".
  String get securityLabel {
    final last4 = cardLast4 ?? '----';
    return switch (security) {
      TabSecurities.cardPreauth => 'Card ••$last4',
      TabSecurities.cashDeposit => 'Deposit ${formatRupees(amountHeldValue)}',
      TabSecurities.houseAccount => 'House account',
      _ => 'None',
    };
  }

  factory TabView.fromJson(Map<String, dynamic> j) {
    final limit = readMoney(j, 'tabLimit');
    final spentText = readMoney(j, 'spent');
    final warn = readInt(j, 'warnAtPercent', 80);
    final percentRaw = j['percentUsed'];
    final percent = percentRaw is num
        ? percentRaw
        : (num.tryParse('${percentRaw ?? ''}') ??
            (moneyValue(limit) == 0 ? 0 : moneyValue(spentText) * 100 / moneyValue(limit)));
    final table = j['table'];
    final openedBy = j['openedBy'];
    final order = j['order'];
    return TabView(
      id: readString(j, 'id'),
      number: readString(j, 'number'),
      guestName: readString(j, 'guestName'),
      mobile: readStringOrNull(j, 'mobile'),
      ageChecked: readBool(j, 'ageChecked'),
      security: readString(j, 'security', TabSecurities.none),
      cardLast4: readStringOrNull(j, 'cardLast4'),
      amountHeld: readMoney(j, 'amountHeld'),
      houseAccount: readStringOrNull(j, 'houseAccount'),
      tabLimit: limit,
      warnAtPercent: warn,
      spent: spentText,
      remaining: j['remaining'] == null
          ? moneyText(moneyValue(limit) - moneyValue(spentText))
          : readMoney(j, 'remaining'),
      percentUsed: percent,
      nearLimit: j['nearLimit'] is bool ? j['nearLimit'] as bool : percent >= warn,
      linkType: readString(j, 'linkType', TabLinkTypes.none),
      linkLabel: readStringOrNull(j, 'linkLabel'),
      table: table is Map ? TableRef.fromJson(asMap(table)) : null,
      status: readString(j, 'status', TabStatuses.open),
      openedAt: readDate(j, 'openedAt'),
      closedAt: readDate(j, 'closedAt'),
      openedBy: openedBy is Map ? TabPerson.fromJson(asMap(openedBy)) : null,
      orderId: readString(j, 'orderId'),
      orderStatus: readStringOrNull(j, 'orderStatus'),
      itemCount: readInt(j, 'itemCount'),
      order: order is Map ? OrderView.fromJson(asMap(order)) : null,
    );
  }
}

/// `counts` block of `GET /tabs`.
class TabCounts {
  const TabCounts({this.open = 0, this.nearLimit = 0, this.closedToday = 0});

  final int open;
  final int nearLimit;
  final int closedToday;

  factory TabCounts.fromJson(Map<String, dynamic> j) => TabCounts(
        open: readInt(j, 'open'),
        nearLimit: readInt(j, 'nearLimit'),
        closedToday: readInt(j, 'closedToday'),
      );
}

/// `GET /tabs` response.
class TabsPage {
  const TabsPage({this.counts = const TabCounts(), this.items = const []});

  final TabCounts counts;
  final List<TabView> items;

  factory TabsPage.fromJson(Map<String, dynamic> j) => TabsPage(
        counts: TabCounts.fromJson(asMap(j['counts'])),
        items: [for (final t in asMaps(j['items'])) TabView.fromJson(t)],
      );
}

/// `POST /tabs/:id/close` response.
class TabCloseResult {
  const TabCloseResult({
    required this.tab,
    required this.orderId,
    this.depositApplied = '0.00',
    this.depositToReturn = '0.00',
  });

  final TabView tab;
  final String orderId;
  final String depositApplied;
  final String depositToReturn;

  factory TabCloseResult.fromJson(Map<String, dynamic> j) => TabCloseResult(
        tab: TabView.fromJson(asMap(j['tab'])),
        orderId: readString(j, 'orderId'),
        depositApplied: readMoney(j, 'depositApplied'),
        depositToReturn: readMoney(j, 'depositToReturn'),
      );
}

/// One entry in a locker's history.
class LockerEvent {
  const LockerEvent({
    required this.kind,
    required this.ml,
    this.by,
    this.note,
    this.createdAt,
  });

  /// One of [LockerEventKinds].
  final String kind;

  /// Served or adjusted ml. Signed for ADJUST.
  final int ml;
  final String? by;
  final String? note;
  final DateTime? createdAt;

  factory LockerEvent.fromJson(Map<String, dynamic> j) => LockerEvent(
        kind: readString(j, 'kind'),
        ml: readInt(j, 'ml'),
        by: readStringOrNull(j, 'by'),
        note: readStringOrNull(j, 'note'),
        createdAt: readDate(j, 'createdAt'),
      );
}

/// `LockerView` from PLAN 1.7.
class LockerView {
  const LockerView({
    required this.id,
    required this.guestName,
    this.mobile,
    this.cardLast4,
    required this.guestLabel,
    this.stockItemId,
    required this.bottleName,
    required this.bottleMl,
    required this.remainingMl,
    this.storedAt,
    this.expiresAt,
    required this.status,
    this.expired = false,
    this.events = const [],
  });

  final String id;
  final String guestName;
  final String? mobile;
  final String? cardLast4;

  /// "Vikram S · ••7720".
  final String guestLabel;
  final String? stockItemId;
  final String bottleName;
  final int bottleMl;
  final int remainingMl;
  final DateTime? storedAt;

  /// Date only.
  final DateTime? expiresAt;

  /// One of [LockerStatuses].
  final String status;
  final bool expired;
  final List<LockerEvent> events;

  bool get isActive => status == LockerStatuses.active;

  factory LockerView.fromJson(Map<String, dynamic> j) => LockerView(
        id: readString(j, 'id'),
        guestName: readString(j, 'guestName'),
        mobile: readStringOrNull(j, 'mobile'),
        cardLast4: readStringOrNull(j, 'cardLast4'),
        guestLabel: readString(j, 'guestLabel', readString(j, 'guestName')),
        stockItemId: readStringOrNull(j, 'stockItemId'),
        bottleName: readString(j, 'bottleName'),
        bottleMl: readInt(j, 'bottleMl'),
        remainingMl: readInt(j, 'remainingMl'),
        storedAt: readDate(j, 'storedAt'),
        expiresAt: readDate(j, 'expiresAt'),
        status: readString(j, 'status', LockerStatuses.active),
        expired: readBool(j, 'expired'),
        events: [for (final e in asMaps(j['events'])) LockerEvent.fromJson(e)],
      );
}

// --- request bodies ----------------------------------------------------------

Map<String, dynamic> _clean(Map<String, dynamic> raw) {
  raw.removeWhere((_, v) => v == null);
  return raw;
}

/// Body of `POST /tabs`. Money is sent as a two-decimal string.
class OpenTabRequest {
  const OpenTabRequest({
    required this.guestName,
    this.mobile,
    required this.ageChecked,
    required this.security,
    this.cardLast4,
    this.amountHeld,
    this.houseAccount,
    required this.tabLimit,
    required this.warnAtPercent,
    required this.linkType,
    this.linkLabel,
    this.tableId,
    this.approvalId,
  });

  final String guestName;
  final String? mobile;
  final bool ageChecked;
  final String security;
  final String? cardLast4;
  final String? amountHeld;
  final String? houseAccount;
  final String tabLimit;
  final int warnAtPercent;
  final String linkType;
  final String? linkLabel;
  final String? tableId;
  final String? approvalId;

  Map<String, dynamic> toJson() => _clean({
        'guestName': guestName,
        'mobile': mobile,
        'ageChecked': ageChecked,
        'security': security,
        'cardLast4': cardLast4,
        'amountHeld': amountHeld,
        'houseAccount': houseAccount,
        'tabLimit': tabLimit,
        'warnAtPercent': warnAtPercent,
        'linkType': linkType,
        'linkLabel': linkLabel,
        'tableId': tableId,
        'approvalId': approvalId,
      });
}

/// Body of `PUT /tabs/:id`. Only the fields that changed are sent.
class TabEditRequest {
  const TabEditRequest({
    this.guestName,
    this.mobile,
    this.tabLimit,
    this.warnAtPercent,
    this.linkType,
    this.linkLabel,
    this.tableId,
  });

  final String? guestName;
  final String? mobile;
  final String? tabLimit;
  final int? warnAtPercent;
  final String? linkType;
  final String? linkLabel;
  final String? tableId;

  Map<String, dynamic> toJson() => _clean({
        'guestName': guestName,
        'mobile': mobile,
        'tabLimit': tabLimit,
        'warnAtPercent': warnAtPercent,
        'linkType': linkType,
        'linkLabel': linkLabel,
        'tableId': tableId,
      });
}

/// Body of `POST /locker`. [expiresAt] is `yyyy-MM-dd`.
class LockerCreateRequest {
  const LockerCreateRequest({
    required this.guestName,
    this.mobile,
    this.cardLast4,
    this.stockItemId,
    required this.bottleName,
    required this.bottleMl,
    required this.remainingMl,
    required this.expiresAt,
    this.note,
  });

  final String guestName;
  final String? mobile;
  final String? cardLast4;
  final String? stockItemId;
  final String bottleName;
  final int bottleMl;
  final int remainingMl;
  final String expiresAt;
  final String? note;

  Map<String, dynamic> toJson() => _clean({
        'guestName': guestName,
        'mobile': mobile,
        'cardLast4': cardLast4,
        'stockItemId': stockItemId,
        'bottleName': bottleName,
        'bottleMl': bottleMl,
        'remainingMl': remainingMl,
        'expiresAt': expiresAt,
        'note': note,
      });
}

/// Body of `PUT /locker/:id`. A changed [remainingMl] writes an ADJUST event.
class LockerEditRequest {
  const LockerEditRequest({
    this.guestName,
    this.mobile,
    this.remainingMl,
    this.expiresAt,
    this.note,
  });

  final String? guestName;
  final String? mobile;
  final int? remainingMl;
  final String? expiresAt;
  final String? note;

  Map<String, dynamic> toJson() => _clean({
        'guestName': guestName,
        'mobile': mobile,
        'remainingMl': remainingMl,
        'expiresAt': expiresAt,
        'note': note,
      });
}
