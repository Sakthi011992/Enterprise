enum AppFeature {
  dashboard,
  products,
  tax,
  users,
  orders,
  appearance,
  // Admin-only features (not grantable to non-admin users via backend)
  localisation,
  settings,
  kioskAdmin,
  branding;

  String get wireValue => name.toUpperCase();

  /// Features that can be granted to non-admin users via the backend.
  static const userGrantable = {
    AppFeature.dashboard,
    AppFeature.products,
    AppFeature.tax,
    AppFeature.users,
    AppFeature.orders,
    AppFeature.appearance,
  };

  static AppFeature? fromWire(String v) {
    try {
      return AppFeature.values.firstWhere((f) => f.wireValue == v.toUpperCase());
    } catch (_) {
      return null;
    }
  }
}
