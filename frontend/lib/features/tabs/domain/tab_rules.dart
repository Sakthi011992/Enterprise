/// Pure tab rules: form validation, limit copy and error words. No widgets, so
/// the tests can call them directly.
library;

import '../../../core/auth/api_error.dart';
import '../../pos/presentation/pos_format.dart';
import '../data/tabs_models.dart';

/// Approval type for a tab opened with security NONE (PLAN 1.6).
const tabNoSecurityApprovalType = 'TAB_NO_SECURITY';

/// Values typed into the open-tab form, before validation.
class OpenTabDraft {
  const OpenTabDraft({
    this.guestName = '',
    this.mobile = '',
    this.ageChecked = false,
    this.security = TabSecurities.cardPreauth,
    this.cardLast4 = '',
    this.amountHeld = '',
    this.houseAccount = '',
    this.tabLimit = '',
    this.linkType = TabLinkTypes.barSeat,
    this.linkLabel = '',
    this.tableId,
  });

  final String guestName;
  final String mobile;
  final bool ageChecked;
  final String security;
  final String cardLast4;
  final String amountHeld;
  final String houseAccount;
  final String tabLimit;
  final String linkType;
  final String linkLabel;
  final String? tableId;
}

/// Field keys used in the error map returned by [validateOpenTab].
abstract final class TabField {
  static const guestName = 'guestName';
  static const ageChecked = 'ageChecked';
  static const cardLast4 = 'cardLast4';
  static const amountHeld = 'amountHeld';
  static const houseAccount = 'houseAccount';
  static const tabLimit = 'tabLimit';
  static const tableId = 'tableId';
}

final _fourDigits = RegExp(r'^\d{4}$');

/// Checks the open-tab form. Returns an empty map when it may be sent. Keys
/// are [TabField] values. [personaLimit] is the signed-in persona's tab limit
/// (null means no limit).
Map<String, String> validateOpenTab(OpenTabDraft draft, {num? personaLimit}) {
  final errors = <String, String>{};
  if (draft.guestName.trim().isEmpty) {
    errors[TabField.guestName] = 'Enter the guest name.';
  }
  if (!draft.ageChecked) {
    errors[TabField.ageChecked] = 'Check the guest is 21 or older (ID seen) before opening a tab.';
  }

  final limit = parseRupeeInput(draft.tabLimit);
  if (limit <= 0) {
    errors[TabField.tabLimit] = 'Enter a tab limit above ₹0.';
  } else if (personaLimit != null && limit > personaLimit) {
    errors[TabField.tabLimit] = personaLimitWarning(limit, personaLimit);
  }

  final held = parseRupeeInput(draft.amountHeld);
  switch (draft.security) {
    case TabSecurities.cardPreauth:
      if (!_fourDigits.hasMatch(draft.cardLast4.trim())) {
        errors[TabField.cardLast4] = 'Enter the last 4 digits of the card.';
      }
      if (held <= 0) errors[TabField.amountHeld] = 'Enter the amount to hold.';
      break;
    case TabSecurities.cashDeposit:
      if (held <= 0) errors[TabField.amountHeld] = 'Enter the deposit amount.';
      break;
    case TabSecurities.houseAccount:
      if (draft.houseAccount.trim().isEmpty) {
        errors[TabField.houseAccount] = 'Enter the house account, such as Corporate: Acme.';
      }
      break;
    default:
      break;
  }

  if (draft.linkType == TabLinkTypes.table && (draft.tableId == null || draft.tableId!.isEmpty)) {
    errors[TabField.tableId] = 'Pick a table.';
  }
  return errors;
}

/// "₹10,000 is above your ₹5,000 limit", shown on the limit field.
String personaLimitWarning(num tabLimit, num personaLimit) =>
    '${formatRupees(tabLimit)} is above your ${formatRupees(personaLimit)} limit';

/// Copy for `TAB_LIMIT_REACHED` on adding items to a tab order.
String tabLimitReachedMessage(ApiError e) {
  final number = e.details?['number']?.toString();
  final limit = num.tryParse(e.details?['limit']?.toString() ?? '');
  final who = number == null ? 'This tab' : 'Tab $number';
  final cap = limit == null ? 'its limit' : 'its ${formatRupees(limit)} limit';
  return '$who has reached $cap. Ask a manager to raise it or close the tab.';
}

/// Words for a tab, locker or table failure. Unknown codes show the server text.
String tabErrorMessage(ApiError e) {
  switch (e.code) {
    case 'TAB_LIMIT_REACHED':
      return tabLimitReachedMessage(e);
    case 'AGE_CHECK_REQUIRED':
      return 'Check the guest is 21 or older (ID seen) before opening a tab.';
    case 'CARD_LAST4_REQUIRED':
      return 'Enter the last 4 digits of the card.';
    case 'DEPOSIT_REQUIRED':
      return 'Enter the deposit amount.';
    case 'HOUSE_ACCOUNT_REQUIRED':
      return 'Enter the house account name.';
    case 'APPROVAL_REQUIRED':
      return 'A manager must approve a tab with no security.';
    case 'LIMIT_EXCEEDED':
      return "That limit is above your tab limit. Ask a manager to set it.";
    case 'TAB_CLOSED':
      return 'This tab is already closed.';
    case 'TAB_EMPTY':
      return 'Add something to the tab before closing it.';
    case 'TAB_NOT_EMPTY':
      return 'Only empty tabs can be voided.';
    case 'TABLE_OCCUPIED':
      return 'That table is taken. Pick another.';
    case 'INVALID_ML':
      return 'Enter an amount of ml above 0.';
    case 'NOT_ENOUGH_LEFT':
      return 'Not that much is left in the bottle.';
    case 'LOCKER_EXPIRED':
      return 'This bottle has expired.';
    default:
      return e.message;
  }
}

/// Short label for a link type, as the form shows it.
String linkTypeLabel(String linkType) => switch (linkType) {
      TabLinkTypes.barSeat => 'Bar counter seat',
      TabLinkTypes.table => 'Table',
      TabLinkTypes.queueToken => 'Walk-in queue token',
      _ => 'Not linked',
    };

/// `yyyy-MM-dd` for date-only fields in the API.
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// "12 Nov" for the stored and expiry columns.
String shortDate(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${months[d.month - 1]}';
}
