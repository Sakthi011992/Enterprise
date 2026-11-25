import 'pos_format.dart';

/// How the entered tenders cover one share on the Pay screen. Pure, so the
/// tests can check it directly.
///
/// Payment rows carry the share's due only. The tip goes in `tipAmount`, not
/// into the payments (PLAN 1.3 point 7 and 1.4 POST /orders/:id/payments).
class TenderPlan {
  const TenderPlan({
    required this.due,
    required this.tip,
    required this.cashApplied,
    required this.upiApplied,
    required this.cardApplied,
    required this.changeToGive,
  });

  /// The share's due, two decimals.
  final double due;

  /// Tip on top of the due, two decimals.
  final double tip;

  /// Cash, UPI and card portions of [due]. Each is two decimals.
  final double cashApplied;
  final double upiApplied;
  final double cardApplied;

  /// Cash handed over, minus the cash applied and the tip. Never negative.
  final double changeToGive;

  double get applied => cashApplied + upiApplied + cardApplied;

  /// Still to pay on this share. Zero or below means covered.
  double get remaining => roundPaise(due - applied);

  bool get isCovered => remaining <= 0.001 && due > 0;

  /// Tip the staff entered, in the wire form the payments body expects.
  String? get tipWire => tip > 0 ? wireMoney(tip) : null;
}

/// Works out the portions from the tenders.
///
/// Cash goes first, up to the due. UPI takes what is left after cash, up to its
/// amount. Card takes the rest when on. The change is cash minus cash applied minus
/// the tip, which matches the Pay board.
TenderPlan planTender({
  required double due,
  required String tipChoice,
  double customTip = 0,
  required double cash,
  required bool useUpi,
  double upi = 0,
  required bool useCard,
}) {
  final dueRounded = roundPaise(due < 0 ? 0 : due);
  final tip = switch (tipChoice) {
    '5' => roundPaise(dueRounded * 0.05),
    '10' => roundPaise(dueRounded * 0.10),
    'custom' => roundPaise(customTip < 0 ? 0 : customTip),
    _ => 0.0,
  };
  final cashApplied = roundPaise(cash <= 0 ? 0 : (cash < dueRounded ? cash : dueRounded));
  final afterCash = roundPaise(dueRounded - cashApplied);
  final upiApplied = useUpi
      ? roundPaise(upi <= 0 ? 0 : (upi < afterCash ? upi : afterCash))
      : 0.0;
  final cardApplied = useCard ? roundPaise(afterCash - upiApplied) : 0.0;
  final change = cash <= 0 ? 0.0 : roundPaise(cash - cashApplied - tip);
  return TenderPlan(
    due: dueRounded,
    tip: tip,
    cashApplied: cashApplied,
    upiApplied: upiApplied,
    cardApplied: cardApplied,
    changeToGive: change < 0 ? 0 : change,
  );
}

/// Quick cash amounts on the keypad.
const quickCashAmounts = [500, 1000, 2000];
