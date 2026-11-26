import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/api_error.dart';
import '../../pos/presentation/modifier_rules.dart';
import '../data/guest_models.dart';
import '../data/guest_repository.dart';
import '../data/guest_store.dart';

/// Where the guest is in the journey.
enum GuestStage { loading, failed, ended, welcome, details, code, ordering }

/// Pages inside [GuestStage.ordering] on a phone. Wider layouts show the menu
/// with the cart and table order beside it, and use [GuestPage.bill] and
/// [GuestPage.billAsked] for the bill.
enum GuestPage { menu, cart, order, bill, billAsked }

/// One line in this guest's own cart.
class GuestCartLine {
  const GuestCartLine({
    required this.product,
    this.optionIds = const {},
    this.quantity = 1,
  });

  final GuestProduct product;
  final Set<String> optionIds;
  final int quantity;

  String get key => '${product.id}|${(optionIds.toList()..sort()).join(',')}';

  double get unitPrice => product.price + modifierDelta(product.modifierGroups, optionIds).toDouble();

  double get total => unitPrice * quantity;

  List<String> get optionNames => [
        for (final g in product.modifierGroups)
          for (final o in g.options)
            if (optionIds.contains(o.id)) o.name,
      ];

  GuestCartLine withQuantity(int q) => GuestCartLine(product: product, optionIds: optionIds, quantity: q);

  GuestRoundItem toItem({String? note}) => GuestRoundItem(
        productId: product.id,
        quantity: quantity,
        note: note,
        modifiers: [
          for (final g in product.modifierGroups)
            for (final o in g.options)
              if (optionIds.contains(o.id)) GuestRoundModifier(groupId: g.id, optionId: o.id),
        ],
      );
}

/// Code screen error state.
class GuestCodeError {
  const GuestCodeError({this.attemptsLeft, this.lockedUntil, this.expired = false, this.message});

  final int? attemptsLeft;
  final DateTime? lockedUntil;
  final bool expired;
  final String? message;
}

class GuestState {
  const GuestState({
    this.stage = GuestStage.loading,
    this.page = GuestPage.menu,
    this.info,
    this.menu,
    this.order,
    this.guest,
    this.name = '',
    this.phone = '',
    this.verification,
    this.codeError,
    this.cart = const [],
    this.note = '',
    this.placing = false,
    this.offline = false,
    this.error,
    this.message,
    this.endedPaid,
  });

  final GuestStage stage;
  final GuestPage page;
  final GuestTableInfo? info;
  final GuestMenu? menu;
  final GuestOrderView? order;

  /// Set once this phone has joined the table.
  final StoredGuest? guest;
  final String name;

  /// 10 digits, without +91.
  final String phone;
  final GuestStart? verification;
  final GuestCodeError? codeError;
  final List<GuestCartLine> cart;
  final String note;

  /// A round is on its way to the server. The cart is locked meanwhile.
  final bool placing;

  /// The last call failed with no response. Shown as "You're offline".
  final bool offline;

  /// Error text for the current screen, cleared on the next action.
  final String? error;

  /// One-off confirmation, e.g. "A waiter is on the way".
  final String? message;

  /// Grand total paid when the session ended with payment.
  final double? endedPaid;

  bool get joined => guest != null;
  GuestSettings get settings => info?.settings ?? const GuestSettings();
  int get cartCount => cart.fold(0, (s, l) => s + l.quantity);
  double get cartTotal => cart.fold(0, (s, l) => s + l.total);
  int quantityOf(String productId) =>
      cart.where((l) => l.product.id == productId).fold(0, (s, l) => s + l.quantity);

  GuestState copyWith({
    GuestStage? stage,
    GuestPage? page,
    GuestTableInfo? info,
    GuestMenu? menu,
    GuestOrderView? order,
    StoredGuest? guest,
    String? name,
    String? phone,
    GuestStart? verification,
    GuestCodeError? codeError,
    bool clearCodeError = false,
    List<GuestCartLine>? cart,
    String? note,
    bool? placing,
    bool? offline,
    String? error,
    bool clearError = false,
    String? message,
    bool clearMessage = false,
    double? endedPaid,
  }) =>
      GuestState(
        stage: stage ?? this.stage,
        page: page ?? this.page,
        info: info ?? this.info,
        menu: menu ?? this.menu,
        order: order ?? this.order,
        guest: guest ?? this.guest,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        verification: verification ?? this.verification,
        codeError: clearCodeError ? null : (codeError ?? this.codeError),
        cart: cart ?? this.cart,
        note: note ?? this.note,
        placing: placing ?? this.placing,
        offline: offline ?? this.offline,
        error: clearError ? null : (error ?? this.error),
        message: clearMessage ? null : (message ?? this.message),
        endedPaid: endedPaid ?? this.endedPaid,
      );
}

/// Validation for the details form. Returns null when valid.
String? validateGuestName(String name) {
  final n = name.trim();
  if (n.isEmpty) return 'Enter your name';
  if (n.length > 40) return 'Keep your name under 40 characters';
  return null;
}

/// Indian mobile: 10 digits starting 6–9, with an optional +91 or 0 in front.
String? normalisePhone(String raw) {
  var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length == 12 && digits.startsWith('91')) digits = digits.substring(2);
  if (digits.length == 11 && digits.startsWith('0')) digits = digits.substring(1);
  if (digits.length != 10 || !RegExp(r'^[6-9]').hasMatch(digits)) return null;
  return digits;
}

String? validateGuestPhone(String raw) =>
    normalisePhone(raw) == null ? 'Enter a 10-digit mobile number' : null;

/// "98765 43210"
String formatPhone(String digits) =>
    digits.length == 10 ? '${digits.substring(0, 5)} ${digits.substring(5)}' : digits;

/// Runs the guest journey for one table QR token.
class GuestController extends StateNotifier<GuestState> {
  GuestController({
    required this.qrToken,
    required GuestRepository repo,
    required GuestStore store,
    Duration? pollInterval,
  })  : _repo = repo,
        _store = store,
        _pollInterval = pollInterval,
        super(const GuestState()) {
    _init();
  }

  final String qrToken;
  final GuestRepository _repo;
  final GuestStore _store;
  final Duration? _pollInterval;

  StreamSubscription<GuestLiveEvent>? _live;
  Timer? _poll;
  String? _roundKey;
  bool _disposed = false;

  void _set(GuestState s) {
    if (!_disposed) state = s;
  }

  Future<void> _init() async {
    _set(const GuestState());
    try {
      final info = await _repo.lookup(qrToken);
      _set(state.copyWith(info: info));
      final stored = await _store.guestFor(qrToken);
      if (stored != null && await _resume(stored)) return;
      final menu = await _loadMenu(preview: true);
      _set(state.copyWith(stage: GuestStage.welcome, menu: menu));
    } on ApiError catch (e) {
      if (e.status == 404 || e.status == 410 || e.code == 'SESSION_CLOSED') {
        _set(state.copyWith(stage: GuestStage.ended));
      } else {
        _set(state.copyWith(stage: GuestStage.failed, offline: e.isNetwork, error: e.message));
      }
    }
  }

  Future<void> retry() => _init();

  Future<GuestMenu?> _loadMenu({bool preview = false}) async {
    try {
      return await _repo.menu(qrToken: preview ? qrToken : null);
    } on ApiError {
      return null;
    }
  }

  /// A returning phone with a stored token skips details and code.
  Future<bool> _resume(StoredGuest stored) async {
    _repo.token = stored.token;
    try {
      final order = await _repo.order();
      if (order.isEnded) {
        await _store.clearGuest(qrToken);
        _repo.token = null;
        return false;
      }
      final menu = await _loadMenu();
      _set(state.copyWith(
        stage: GuestStage.ordering,
        page: GuestPage.menu,
        guest: stored,
        name: stored.name,
        phone: stored.phone,
        order: order,
        menu: menu,
      ));
      _startLive();
      return true;
    } on ApiError catch (e) {
      if (e.isNetwork) rethrow;
      await _store.clearGuest(qrToken);
      _repo.token = null;
      return false;
    }
  }

  // --- welcome / details / code ---------------------------------------------

  /// "See menu & order", "Call a waiter" and "View bill" all need a joined guest.
  void begin({GuestPage page = GuestPage.menu}) {
    if (state.joined) {
      _set(state.copyWith(stage: GuestStage.ordering, page: page, clearError: true));
    } else {
      _set(state.copyWith(stage: GuestStage.details, clearError: true));
    }
  }

  void backToWelcome() => _set(state.copyWith(stage: GuestStage.welcome, clearError: true));

  void backToDetails() =>
      _set(state.copyWith(stage: GuestStage.details, clearError: true, clearCodeError: true));

  /// Returns field errors, or an empty map when the call went through.
  Future<Map<String, String>> submitDetails({
    required String name,
    required String phone,
    required bool consent,
  }) async {
    final errors = <String, String>{};
    final nameErr = validateGuestName(name);
    final phoneErr = validateGuestPhone(phone);
    if (nameErr != null) errors['name'] = nameErr;
    if (phoneErr != null) errors['phone'] = phoneErr;
    if (!consent) errors['consent'] = 'Tick the box so we can use your number for this order';
    if (errors.isNotEmpty) return errors;
    final digits = normalisePhone(phone)!;
    _set(state.copyWith(name: name.trim(), phone: digits, clearError: true));
    await _startVerification();
    return const {};
  }

  Future<void> _startVerification() async {
    try {
      final start = await _repo.start(
        qrToken,
        deviceKey: await _store.deviceKey(),
        name: state.name,
        phone: '+91${state.phone}',
        consent: true,
      );
      _set(state.copyWith(
        stage: GuestStage.code,
        verification: start,
        clearCodeError: true,
        offline: false,
      ));
    } on ApiError catch (e) {
      _set(state.copyWith(offline: e.isNetwork, error: _startError(e)));
    }
  }

  String _startError(ApiError e) => switch (e.code) {
        'TABLE_NOT_SEATED' => 'Ask staff to seat you to start ordering.',
        'RATE_LIMITED' => 'Too many tries. Wait a minute and try again.',
        'CONSENT_REQUIRED' => 'Tick the box so we can use your number for this order',
        _ => e.isNetwork ? "You're offline — we'll retry" : e.message,
      };

  /// After CODE_EXPIRED: asks for a fresh challenge with the same details.
  Future<void> restartVerification() => _startVerification();

  Future<void> submitCode(String code) async {
    final v = state.verification;
    if (v == null) return;
    final lock = state.codeError?.lockedUntil;
    if (lock != null && DateTime.now().isBefore(lock)) return;
    try {
      final join = await _repo.verify(qrToken, verificationId: v.verificationId, code: code);
      final stored = StoredGuest(
        token: join.guestToken,
        participantId: join.participant.id,
        name: join.participant.name.isEmpty ? state.name : join.participant.name,
        phone: state.phone,
        ageConfirmed: join.ageConfirmed,
      );
      await _store.saveGuest(qrToken, stored);
      _repo.token = stored.token;
      final menu = await _loadMenu();
      _set(state.copyWith(
        stage: GuestStage.ordering,
        page: GuestPage.menu,
        guest: stored,
        menu: menu,
        clearCodeError: true,
        offline: false,
      ));
      _startLive();
      await refreshOrder();
    } on ApiError catch (e) {
      final error = switch (e.code) {
        'CODE_INVALID' => GuestCodeError(attemptsLeft: e.intDetail('attemptsLeft')),
        'CODE_LOCKED' => GuestCodeError(lockedUntil: _retryAt(e)),
        'CODE_EXPIRED' => const GuestCodeError(expired: true),
        _ => GuestCodeError(message: e.isNetwork ? "You're offline — we'll retry" : e.message),
      };
      _set(state.copyWith(codeError: error, offline: e.isNetwork));
    }
  }

  static DateTime _retryAt(ApiError e) {
    final raw = e.details?['retryAfter'];
    if (raw is num) return DateTime.now().add(Duration(seconds: raw.toInt()));
    if (raw is String) {
      final at = DateTime.tryParse(raw);
      if (at != null) return at.toLocal();
      final secs = int.tryParse(raw);
      if (secs != null) return DateTime.now().add(Duration(seconds: secs));
    }
    return DateTime.now().add(const Duration(minutes: 10));
  }

  // --- navigation -------------------------------------------------------------

  void goTo(GuestPage page) =>
      _set(state.copyWith(stage: GuestStage.ordering, page: page, clearError: true, clearMessage: true));

  void clearMessage() => _set(state.copyWith(clearMessage: true, clearError: true));

  // --- cart -------------------------------------------------------------------

  bool get ageConfirmed => state.guest?.ageConfirmed ?? false;

  /// True when adding [product] must first ask the age question.
  bool needsAgeCheck(GuestProduct product) =>
      state.settings.ageGate && product.isAlcohol && !ageConfirmed;

  Future<bool> confirmAge() async {
    final g = state.guest;
    if (g == null) return false;
    try {
      await _repo.confirmAge();
      final next = g.copyWith(ageConfirmed: true);
      await _store.saveGuest(qrToken, next);
      _set(state.copyWith(guest: next, offline: false));
      return true;
    } on ApiError catch (e) {
      _set(state.copyWith(offline: e.isNetwork, error: e.isNetwork ? "You're offline — we'll retry" : e.message));
      return false;
    }
  }

  void add(GuestProduct product, {Set<String> optionIds = const {}, int quantity = 1}) {
    if (state.placing || !product.available) return;
    final line = GuestCartLine(product: product, optionIds: optionIds, quantity: quantity);
    final cart = [...state.cart];
    final i = cart.indexWhere((l) => l.key == line.key);
    if (i >= 0) {
      cart[i] = cart[i].withQuantity(cart[i].quantity + quantity);
    } else {
      cart.add(line);
    }
    _roundKey = null;
    _set(state.copyWith(cart: cart));
  }

  /// Stepper on a menu row: changes the most recent cart line for the product.
  void changeProduct(GuestProduct product, int delta) {
    final i = state.cart.lastIndexWhere((l) => l.product.id == product.id);
    if (i < 0) {
      if (delta > 0) add(product);
      return;
    }
    setQuantity(state.cart[i].key, state.cart[i].quantity + delta);
  }

  void setQuantity(String key, int quantity) {
    if (state.placing) return;
    final cart = [
      for (final l in state.cart)
        if (l.key != key)
          l
        else if (quantity > 0)
          l.withQuantity(quantity.clamp(1, 10)),
    ];
    _roundKey = null;
    _set(state.copyWith(cart: cart));
  }

  void setNote(String note) => _set(state.copyWith(note: note));

  /// Sends this guest's cart as one round. The same `roundKey` is reused for
  /// retries, so a flaky network can't place it twice.
  Future<void> placeOrder() async {
    if (state.placing || state.cart.isEmpty) return;
    _roundKey ??= 'rk-${newDeviceKey()}';
    _set(state.copyWith(placing: true, clearError: true));
    final note = state.note.trim();
    final items = [
      for (var i = 0; i < state.cart.length; i++)
        state.cart[i].toItem(note: i == 0 && note.isNotEmpty ? note : null),
    ];
    try {
      await _repo.placeRound(_roundKey!, items);
      _roundKey = null;
      _set(state.copyWith(
        placing: false,
        offline: false,
        cart: const [],
        note: '',
        page: GuestPage.order,
      ));
      await refreshOrder();
    } on ApiError catch (e) {
      if (e.isNetwork) {
        // Keep `placing` and the key; the poll tick retries.
        _set(state.copyWith(offline: true));
        return;
      }
      _set(state.copyWith(placing: false, offline: false, error: _roundError(e)));
    }
  }

  String _roundError(ApiError e) => switch (e.code) {
        'ITEM_UNAVAILABLE' => 'Something in your cart has just sold out. Remove it and try again.',
        'MODIFIER_RULE' => 'Some choices are missing. Open the item and pick again.',
        'ROUND_TOO_LARGE' => 'That is a big round. Split it into two orders.',
        'AGE_NOT_CONFIRMED' => 'Confirm your age to order drinks with alcohol.',
        'SESSION_CLOSED' => "This table's session has ended.",
        'GUEST_ORDERING_OFF' => 'Ordering from the table is off right now. Ask your waiter.',
        'TABLE_NOT_SEATED' => 'Ask staff to seat you to start ordering.',
        'RATE_LIMITED' => 'Too many orders in a minute. Try again shortly.',
        _ => e.message,
      };

  Future<void> cancelRound(String roundId) async {
    try {
      await _repo.cancelRound(roundId);
      await refreshOrder();
    } on ApiError catch (e) {
      _set(state.copyWith(offline: e.isNetwork, error: e.isNetwork ? "You're offline — we'll retry" : e.message));
    }
  }

  // --- bill and service -------------------------------------------------------

  Future<void> askForBill() async {
    try {
      await _repo.checkout(mode: 'WAITER');
      _set(state.copyWith(page: GuestPage.billAsked, offline: false));
      await refreshOrder();
    } on ApiError catch (e) {
      _set(state.copyWith(offline: e.isNetwork, error: e.isNetwork ? "You're offline — we'll retry" : e.message));
    }
  }

  Future<void> callWaiter() async {
    try {
      await _repo.serviceRequest(GuestServiceType.callWaiter);
      _set(state.copyWith(message: 'A waiter is on the way', offline: false));
    } on ApiError catch (e) {
      _set(state.copyWith(offline: e.isNetwork, error: e.isNetwork ? "You're offline — we'll retry" : e.message));
    }
  }

  // --- live -------------------------------------------------------------------

  void _startLive() {
    _live?.cancel();
    _live = _repo.live().listen((event) {
      switch (event) {
        case GuestOrderUpdated(:final view):
          _applyOrder(view);
        case GuestSessionClosed():
          _ended();
      }
    });
    final interval = _pollInterval;
    if (interval != null) {
      _poll?.cancel();
      _poll = Timer.periodic(interval, (_) => pollTick());
    }
  }

  /// One poll step: retries a round stuck offline, and refreshes the order
  /// while the socket is down.
  Future<void> pollTick() async {
    if (state.placing && state.offline) {
      _set(state.copyWith(placing: false));
      await placeOrder();
    }
    if (!_repo.liveConnected.value || state.offline) await refreshOrder();
  }

  Future<void> refreshOrder() async {
    if (!state.joined) return;
    try {
      final view = await _repo.order();
      _set(state.copyWith(offline: false));
      _applyOrder(view);
    } on ApiError catch (e) {
      if (e.isNetwork) {
        _set(state.copyWith(offline: true));
      } else if (e.status == 401 || e.code == 'SESSION_CLOSED') {
        await _ended();
      }
    }
  }

  void _applyOrder(GuestOrderView view) {
    if (view.isEnded) {
      _ended(paid: view.totals.paid > 0 ? view.totals.paid : view.totals.grandTotal);
      _set(state.copyWith(order: view));
      return;
    }
    final asked = view.checkout.requested;
    final page = asked && state.page == GuestPage.bill ? GuestPage.billAsked : state.page;
    _set(state.copyWith(order: view, page: page));
  }

  Future<void> _ended({double? paid}) async {
    _poll?.cancel();
    _poll = null;
    await _live?.cancel();
    _live = null;
    await _store.clearGuest(qrToken);
    _repo.token = null;
    _set(state.copyWith(
      stage: GuestStage.ended,
      endedPaid: paid ?? state.order?.totals.grandTotal,
    ));
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _live?.cancel();
    super.dispose();
  }
}

final guestControllerProvider =
    StateNotifierProvider.autoDispose.family<GuestController, GuestState, String>(
  (ref, qrToken) => GuestController(
    qrToken: qrToken,
    repo: ref.watch(guestRepositoryProvider),
    store: ref.watch(guestStoreProvider),
    pollInterval: ref.watch(guestPollIntervalProvider),
  ),
);
