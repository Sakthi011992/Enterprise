import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/auth/api_error.dart';
import 'guest_models.dart';
import 'guest_repository.dart';

/// In-memory guest backend with the design's data: Pegs & Bottles, table R4,
/// Arun already ordering, Deepa joining. With [simulate] on, rounds move
/// through the kitchen states every few seconds so the live view can be seen.
///
/// QR tokens pick a scenario in the mock run: one containing `seat` is not
/// seated, `pin` uses the table PIN, `direct` routes straight to the kitchen.
/// Codes: static OTP `246810`, table PIN `4817`.
class MockGuestRepository implements GuestRepository {
  MockGuestRepository({
    this.simulate = false,
    this.tick = const Duration(seconds: 4),
    GuestRouting? routing,
    GuestVerifyMethod? method,
    bool? seated,
    this.ageGate = true,
    this.minAge = 25,
    DateTime Function()? clock,
    bool seedRounds = true,
  })  : _routing = routing,
        _method = method,
        _seated = seated,
        _clock = clock ?? DateTime.now {
    if (seedRounds) _seed();
    if (simulate) _timer = Timer.periodic(tick, (_) => advance());
  }

  static const staticOtp = '246810';
  static const tablePin = '4817';

  final bool simulate;
  final Duration tick;
  final bool ageGate;
  final int minAge;
  final DateTime Function() _clock;
  final GuestRouting? _routing;
  final GuestVerifyMethod? _method;
  final bool? _seated;

  /// Network failure switch for offline tests.
  bool offline = false;

  String? _token;
  String _qr = 'R4';
  Timer? _timer;
  final _events = StreamController<GuestLiveEvent>.broadcast();
  final _connected = ValueNotifier<bool>(true);

  final List<GuestRound> _rounds = [];
  final Map<String, String> _roundKeys = {};
  final Map<String, _Verification> _verifications = {};
  final Map<String, String> _participants = {}; // id -> name
  final Set<String> _validTokens = {};
  bool _billAsked = false;
  int _billTicks = 0;
  GuestOrderStatus _status = GuestOrderStatus.open;
  int _seq = 0;

  /// Calls made, for tests.
  final List<String> calls = [];

  GuestRouting get routing =>
      _routing ?? (_qr.toLowerCase().contains('direct') ? GuestRouting.direct : GuestRouting.waiter);

  GuestVerifyMethod get method =>
      _method ?? (_qr.toLowerCase().contains('pin') ? GuestVerifyMethod.tablePin : GuestVerifyMethod.staticOtp);

  bool get seated => _seated ?? !_qr.toLowerCase().contains('seat');

  int get _codeLength => method == GuestVerifyMethod.tablePin ? 4 : 6;

  void _seed() {
    final now = _clock();
    _participants['p-arun'] = 'Arun';
    _rounds.addAll([
      GuestRound(
        id: 'r-arun-1',
        by: 'Arun',
        status: GuestRoundStatus.confirmed,
        participantId: 'p-arun',
        createdAt: now.subtract(const Duration(minutes: 9)),
        lines: const [
          GuestLine(name: 'House Red Wine', qty: 1, lineTotal: 420, state: GuestLineState.sent),
        ],
      ),
      GuestRound(
        id: 'r-arun-2',
        by: 'Arun',
        status: GuestRoundStatus.confirmed,
        participantId: 'p-arun',
        createdAt: now.subtract(const Duration(minutes: 6)),
        lines: const [
          GuestLine(
              name: 'Chicken Wings (8 pc)',
              modifiers: ['Hot'],
              qty: 1,
              lineTotal: 350,
              state: GuestLineState.ready),
          GuestLine(name: 'Chicken Biryani', qty: 1, lineTotal: 380, state: GuestLineState.cooking),
          GuestLine(name: 'Premium Lager 650 ml', qty: 1, lineTotal: 360, state: GuestLineState.served),
        ],
      ),
    ]);
  }

  Future<void> _net() async {
    calls.add('net');
    if (offline) {
      throw const ApiError(status: 0, message: "Couldn't reach the server. Check your connection.");
    }
  }

  void _requireToken() {
    final t = _token;
    if (t == null || !_isValid(t)) {
      throw const ApiError(status: 401, code: 'UNAUTHORIZED', message: 'Guest token is not valid');
    }
    if (_status == GuestOrderStatus.closed) {
      throw const ApiError(status: 401, code: 'SESSION_CLOSED', message: 'Session closed');
    }
  }

  /// Tokens look like `mock.<participantId>.<name>`, so a browser refresh in
  /// the mock run (which loses memory) still rejoins as the same person.
  bool _isValid(String token) {
    if (_validTokens.contains(token)) return true;
    final parts = token.split('.');
    if (parts.length >= 3 && parts.first == 'mock' && !simulate) return false;
    if (parts.length >= 3 && parts.first == 'mock') {
      _participants[parts[1]] = parts.sublist(2).join('.');
      _validTokens.add(token);
      return true;
    }
    return false;
  }

  String? get _me {
    final t = _token;
    if (t == null) return null;
    final parts = t.split('.');
    return parts.length >= 3 ? parts[1] : null;
  }

  /// Ends the session, as staff closing the paid order would.
  void closeSession() {
    _status = GuestOrderStatus.closed;
    _validTokens.clear();
    _emitClosed();
  }

  // --- GuestRepository --------------------------------------------------------

  @override
  set token(String? value) => _token = value;

  @override
  Future<GuestTableInfo> lookup(String qrToken) async {
    await _net();
    _qr = qrToken;
    if (qrToken.toLowerCase().contains('ended')) {
      throw const ApiError(status: 404, code: 'NOT_FOUND', message: 'Unknown table');
    }
    return GuestTableInfo(
      tableId: 't-r4',
      tableName: 'R4',
      areaName: 'Rooftop',
      outletName: 'Pegs & Bottles',
      themeId: 'pegs-and-bottles',
      settings: GuestSettings(
        routing: routing,
        method: method,
        codeLength: _codeLength,
        ageGate: ageGate,
        minAge: minAge,
      ),
      seated: seated,
      sessionOpen: true,
    );
  }

  @override
  Future<GuestStart> start(
    String qrToken, {
    required String deviceKey,
    required String name,
    required String phone,
    required bool consent,
  }) async {
    await _net();
    if (!seated) {
      throw const ApiError(status: 409, code: 'TABLE_NOT_SEATED', message: 'Table is not seated');
    }
    if (!consent) {
      throw const ApiError(status: 400, code: 'CONSENT_REQUIRED', message: 'Consent is required');
    }
    final id = 'v-${++_seq}';
    _verifications[id] = _Verification(
      deviceKey: deviceKey,
      name: name,
      phone: phone,
      expiresAt: _clock().add(const Duration(minutes: 10)),
    );
    return GuestStart(verificationId: id, method: method, codeLength: _codeLength);
  }

  @override
  Future<GuestJoin> verify(String qrToken, {required String verificationId, required String code}) async {
    await _net();
    final v = _verifications[verificationId];
    if (v == null) {
      throw const ApiError(status: 410, code: 'CODE_EXPIRED', message: 'Code expired');
    }
    final now = _clock();
    if (v.lockedUntil != null && now.isBefore(v.lockedUntil!)) {
      throw ApiError(
        status: 429,
        code: 'CODE_LOCKED',
        message: 'Too many tries',
        details: {'retryAfter': v.lockedUntil!.difference(now).inSeconds},
      );
    }
    if (now.isAfter(v.expiresAt)) {
      throw const ApiError(status: 410, code: 'CODE_EXPIRED', message: 'Code expired');
    }
    final expected = method == GuestVerifyMethod.tablePin ? tablePin : staticOtp;
    if (code != expected) {
      v.attempts++;
      if (v.attempts >= 5) {
        v.lockedUntil = now.add(const Duration(minutes: 10));
        throw const ApiError(
          status: 429,
          code: 'CODE_LOCKED',
          message: 'Too many tries',
          details: {'retryAfter': 600},
        );
      }
      throw ApiError(
        status: 401,
        code: 'CODE_INVALID',
        message: "That code doesn't match",
        details: {'attemptsLeft': 5 - v.attempts},
      );
    }
    final participantId = 'p-${v.deviceKey.hashCode.abs()}';
    _participants[participantId] = v.name;
    final token = 'mock.$participantId.${v.name}';
    _validTokens.add(token);
    return GuestJoin(
      guestToken: token,
      sessionId: 's-r4',
      participant: GuestParticipant(id: participantId, name: v.name),
    );
  }

  @override
  Future<GuestMenu> menu({String? qrToken}) async {
    await _net();
    return mockGuestMenu;
  }

  @override
  Future<GuestRoundView> placeRound(String roundKey, List<GuestRoundItem> items) async {
    await _net();
    _requireToken();
    final existing = _roundKeys[roundKey];
    if (existing != null) return _rounds.firstWhere((r) => r.id == existing);
    final unavailable = [
      for (final i in items)
        if (mockGuestMenu.product(i.productId)?.available != true) i.productId,
    ];
    if (unavailable.isNotEmpty) {
      throw ApiError(
        status: 409,
        code: 'ITEM_UNAVAILABLE',
        message: 'Some items are sold out',
        details: {'productIds': unavailable},
      );
    }
    final direct = routing == GuestRouting.direct;
    final me = _me ?? 'p-me';
    final round = GuestRound(
      id: 'r-${++_seq}',
      by: _participants[me] ?? 'You',
      participantId: me,
      status: direct ? GuestRoundStatus.confirmed : GuestRoundStatus.pending,
      createdAt: _clock(),
      lines: [for (final i in items) _lineFor(i, direct)],
    );
    _rounds.add(round);
    _roundKeys[roundKey] = round.id;
    _emit();
    return round.copyWith(mine: true);
  }

  GuestLine _lineFor(GuestRoundItem item, bool direct) {
    final p = mockGuestMenu.product(item.productId)!;
    final mods = <String>[];
    double delta = 0;
    for (final m in item.modifiers) {
      for (final g in p.modifierGroups) {
        for (final o in g.options) {
          if (o.id == m.optionId) {
            mods.add(o.name);
            delta += o.priceDeltaValue;
          }
        }
      }
    }
    return GuestLine(
      name: p.name,
      modifiers: mods,
      qty: item.quantity,
      lineTotal: (p.price + delta) * item.quantity,
      state: direct ? GuestLineState.sent : GuestLineState.waitingWaiter,
      updatedAt: _clock(),
    );
  }

  @override
  Future<void> cancelRound(String roundId) async {
    await _net();
    _requireToken();
    final i = _rounds.indexWhere((r) => r.id == roundId);
    if (i < 0 || _rounds[i].status != GuestRoundStatus.pending) {
      throw const ApiError(status: 409, code: 'NOT_PENDING', message: 'Round already confirmed');
    }
    _rounds[i] = _rounds[i].copyWith(
      status: GuestRoundStatus.cancelled,
      lines: [for (final l in _rounds[i].lines) l.copyWith(state: GuestLineState.cancelled)],
    );
    _emit();
  }

  /// Staff-side reject, for tests and the simulation.
  void reject(String roundId, String reason) {
    final i = _rounds.indexWhere((r) => r.id == roundId);
    if (i < 0) return;
    _rounds[i] = _rounds[i].copyWith(
      status: GuestRoundStatus.rejected,
      rejectReason: reason,
      lines: [for (final l in _rounds[i].lines) l.copyWith(state: GuestLineState.cancelled)],
    );
    _emit();
  }

  GuestOrderView _view() {
    final me = _me;
    final rounds = [
      for (final r in _rounds.reversed) r.copyWith(mine: me != null && r.participantId == me),
    ];
    final subtotal = _rounds
        .expand((r) => r.lines)
        .where((l) => l.state != GuestLineState.cancelled)
        .fold<double>(0, (s, l) => s + l.lineTotal);
    final service = (subtotal * 0.05).roundToDouble();
    final tax = ((subtotal + service) * 0.05).roundToDouble();
    final grand = subtotal + service + tax;
    final paid = _status == GuestOrderStatus.paid || _status == GuestOrderStatus.closed ? grand : 0.0;
    return GuestOrderView(
      table: 'R4',
      status: _status,
      rounds: rounds,
      totals: GuestTotals(
        subtotal: subtotal,
        serviceCharge: service,
        tax: tax,
        grandTotal: grand,
        paid: paid,
        due: grand - paid,
      ),
      checkout: GuestCheckoutState(requested: _billAsked),
      atTable: _participants.length,
    );
  }

  @override
  Future<GuestOrderView> order() async {
    await _net();
    final t = _token;
    if (t == null || !_isValid(t)) {
      throw const ApiError(status: 401, code: 'UNAUTHORIZED', message: 'Guest token is not valid');
    }
    return _view();
  }

  @override
  Future<GuestServiceRequest> serviceRequest(GuestServiceType type) async {
    await _net();
    _requireToken();
    if (type == GuestServiceType.bill) _billAsked = true;
    return GuestServiceRequest(id: 'sr-${++_seq}', type: serviceTypeWire(type));
  }

  @override
  Future<GuestCheckout> checkout({String mode = 'WAITER'}) async {
    await _net();
    _requireToken();
    if (mode != 'WAITER') {
      throw const ApiError(status: 501, code: 'NOT_AVAILABLE', message: 'Online payment is coming soon');
    }
    _billAsked = true;
    _emit();
    return const GuestCheckout(mode: 'WAITER', requestId: 'sr-bill');
  }

  @override
  Future<void> confirmAge() async {
    await _net();
    _requireToken();
  }

  // --- simulation -------------------------------------------------------------

  /// Moves every round one step: waiter confirms, then kitchen states.
  void advance() {
    var changed = false;
    for (var i = 0; i < _rounds.length; i++) {
      final r = _rounds[i];
      if (r.status == GuestRoundStatus.pending) {
        _rounds[i] = r.copyWith(
          status: GuestRoundStatus.confirmed,
          lines: [for (final l in r.lines) l.copyWith(state: GuestLineState.sent, updatedAt: _clock())],
        );
        changed = true;
        continue;
      }
      if (r.status != GuestRoundStatus.confirmed) continue;
      final next = [
        for (final l in r.lines)
          switch (l.state) {
            GuestLineState.sent => l.copyWith(state: GuestLineState.cooking, updatedAt: _clock()),
            GuestLineState.cooking => l.copyWith(state: GuestLineState.ready, updatedAt: _clock()),
            GuestLineState.ready => l.copyWith(state: GuestLineState.served, updatedAt: _clock()),
            _ => l,
          },
      ];
      if (!listEquals([for (final l in next) l.state], [for (final l in r.lines) l.state])) {
        _rounds[i] = r.copyWith(lines: next);
        changed = true;
      }
    }
    if (_billAsked && _status == GuestOrderStatus.open) {
      _billTicks++;
      if (_billTicks >= 3) {
        _status = GuestOrderStatus.paid;
        changed = true;
      }
    }
    if (changed) _emit();
  }

  void _emit() {
    if (!_events.isClosed && _token != null && _isValid(_token!)) {
      _events.add(GuestOrderUpdated(_view()));
    }
  }

  void _emitClosed() {
    if (!_events.isClosed) _events.add(const GuestSessionClosed());
  }

  @override
  Stream<GuestLiveEvent> live() => _events.stream;

  @override
  ValueListenable<bool> get liveConnected => _connected;

  @override
  void dispose() {
    _timer?.cancel();
    _events.close();
  }
}

class _Verification {
  _Verification({
    required this.deviceKey,
    required this.name,
    required this.phone,
    required this.expiresAt,
  });

  final String deviceKey;
  final String name;
  final String phone;
  final DateTime expiresAt;
  int attempts = 0;
  DateTime? lockedUntil;
}

GuestProduct _p(
  String id,
  String cat,
  String name,
  String desc,
  double price, {
  double? base,
  bool alcohol = false,
  bool available = true,
  bool featured = false,
  List<PosModifierGroup> mods = const [],
}) =>
    GuestProduct(
      id: id,
      name: name,
      categoryId: cat,
      description: desc,
      price: price,
      basePrice: base,
      isAlcohol: alcohol,
      available: available,
      featured: featured,
      modifierGroups: mods,
    );

const _ice = PosModifierGroup(id: 'g-ice', name: 'Ice', minSelect: 1, maxSelect: 1, options: [
  PosModifierOption(id: 'o-rocks', name: 'On the rocks'),
  PosModifierOption(id: 'o-noice', name: 'No ice'),
]);
const _extras = PosModifierGroup(id: 'g-extras', name: 'Extras', minSelect: 0, maxSelect: 2, options: [
  PosModifierOption(id: 'o-mint', name: 'Extra mint', priceDelta: '30.00'),
  PosModifierOption(id: 'o-lime', name: 'Extra lime', priceDelta: '20.00'),
]);
const _sauce = PosModifierGroup(id: 'g-sauce', name: 'Sauce', minSelect: 1, maxSelect: 1, options: [
  PosModifierOption(id: 'o-hot', name: 'Hot'),
  PosModifierOption(id: 'o-bbq', name: 'BBQ'),
]);

/// The mock menu, from the design board.
final GuestMenu mockGuestMenu = GuestMenu(
  happyHour: const GuestHappyHour(label: '30% off cocktails', until: '8 pm'),
  categories: [
    GuestCategory(id: 'c-cocktails', name: 'Cocktails', products: [
      _p('p-mojito', 'c-cocktails', 'Classic Mojito', 'Rum, mint, lime', 245,
          base: 350, alcohol: true, featured: true, mods: const [_ice, _extras]),
      _p('p-lit', 'c-cocktails', 'Long Island Iced Tea', 'Strong', 343, base: 490, alcohol: true),
      _p('p-colada', 'c-cocktails', 'Virgin Colada', 'No alcohol', 220),
      _p('p-cognac', 'c-cocktails', 'Aged Cognac Sour', 'Sold out tonight', 520,
          alcohol: true, available: false),
    ]),
    GuestCategory(id: 'c-beer', name: 'Beer', products: [
      _p('p-lager', 'c-beer', 'Premium Lager 650 ml', 'Chilled bottle', 360,
          alcohol: true, featured: true),
      _p('p-wheat', 'c-beer', 'Wheat Beer 330 ml', 'Craft, on tap', 290, alcohol: true),
    ]),
    GuestCategory(id: 'c-wine', name: 'Wine', products: [
      _p('p-redwine', 'c-wine', 'House Red Wine', 'By the glass', 420, alcohol: true),
    ]),
    GuestCategory(id: 'c-food', name: 'Food', products: [
      _p('p-biryani', 'c-food', 'Chicken Biryani', 'Fragrant rice, raita', 380, featured: true),
      _p('p-wings', 'c-food', 'Chicken Wings (8 pc)', 'Hot or BBQ', 350,
          featured: true, mods: const [_sauce]),
      _p('p-paneer', 'c-food', 'Paneer Tikka', 'Tandoor, mint chutney', 320),
    ]),
    GuestCategory(id: 'c-desserts', name: 'Desserts', products: [
      _p('p-jamun', 'c-desserts', 'Gulab Jamun', 'Two pieces, warm', 160),
    ]),
  ],
);
