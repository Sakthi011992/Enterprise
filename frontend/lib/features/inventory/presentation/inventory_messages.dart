import '../../../core/auth/api_error.dart';
import '../../pos/presentation/pos_format.dart';

/// Friendly text for the Phase 3 error codes the inventory and procurement
/// screens meet. Unknown codes fall back to the server message.
String inventoryErrorText(Object error) {
  final e = ApiError.from(error);
  if (e.isNetwork) return "You're offline. Keep working and try again when you reconnect.";
  switch (e.code) {
    case 'INSUFFICIENT_STOCK':
      final display = e.stringDetail('onHandDisplay');
      return display == null
          ? 'Not enough stock at this location. Check the count or pick another location.'
          : 'Only $display in stock here. Check the count or pick another location.';
    case 'PHOTO_REQUIRED':
      return 'Add a photo. Wastage above ${formatRupees(2000)} needs one.';
    case 'INVALID_REASON':
      return 'Pick a reason from the list.';
    case 'SAME_LOCATION':
      return 'Choose two different locations.';
    case 'EMPTY_TRANSFER':
    case 'EMPTY_PO':
      return 'Add at least one line first.';
    case 'COUNT_ALREADY_OPEN':
      return 'A count is already open for this location. Continue it instead.';
    case 'COUNT_NOT_OPEN':
      return 'This count is no longer open for changes.';
    case 'COUNT_NOT_SUBMITTED':
      return 'Submit the count before posting it.';
    case 'COUNT_POSTED':
      return 'This count is already posted.';
    case 'NOTHING_COUNTED':
      return 'Count at least one item before submitting.';
    case 'PO_NOT_EDITABLE':
      return 'This purchase order can no longer be edited.';
    case 'PO_NOT_PENDING':
      return 'This purchase order is not waiting for approval.';
    case 'PO_NOT_APPROVED':
      return 'Approve the purchase order before sending it.';
    case 'PO_RECEIVED':
      return 'A received purchase order cannot be cancelled.';
    case 'PO_NOT_RECEIVABLE':
      return 'Send the purchase order to the vendor before receiving against it.';
    case 'VENDOR_MISSING':
      return 'Some items have no preferred vendor. Set a vendor on those items first.';
    case 'GRN_POSTED':
      return 'This goods receipt is already posted.';
    case 'INVOICE_NO_REQUIRED':
      return 'Enter the vendor invoice number before posting.';
    case 'PERMIT_REQUIRED':
      return 'Liquor needs a transport permit number before posting.';
    case 'INVALID_QTY':
      return 'Quantities must be 0 or more, and damaged cannot be more than received.';
    case 'VENDOR_EXISTS':
      return 'A vendor with this name already exists.';
    case 'STOCK_ITEM_EXISTS':
      return 'A stock item with this name already exists.';
    case 'LOCATION_EXISTS':
      return 'A location with this name already exists.';
    case 'RECIPE_DUPLICATE_VARIANT':
      return 'Each variant can have only one recipe.';
    case 'PERMISSION_DENIED':
      return "You don't have permission for that.";
    default:
      return e.message;
  }
}
