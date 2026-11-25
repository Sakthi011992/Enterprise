/// Permission keys mirrored from the backend catalog (PLAN 1.1).
/// The backend is the source of truth; these constants only name keys.
abstract class Perm {
  static const salesOrdersTake = 'sales.orders.take';
  static const salesPaymentsTake = 'sales.payments.take';
  static const salesDiscountGive = 'sales.discount.give';
  static const salesVoid = 'sales.void';
  static const salesTabOpen = 'sales.tab.open';
  static const menuEdit = 'menu.edit';
  static const menuMark86 = 'menu.mark86';
  static const stockCount = 'stock.count';
  static const stockPurchaseOrders = 'stock.purchaseOrders';
  static const guestsQueue = 'guests.queue';
  static const displaysControl = 'displays.control';
  static const reportsView = 'reports.view';
  static const adminUsers = 'admin.users';
  static const adminSettings = 'admin.settings';
  static const adminThemes = 'admin.themes';
}
