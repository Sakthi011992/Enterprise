enum AppFeature {
  dashboard,
  products,
  tax,
  users,
  orders,
  appearance;

  String get wireValue => name.toUpperCase();

  static AppFeature? fromWire(String v) {
    try {
      return AppFeature.values.firstWhere((f) => f.wireValue == v.toUpperCase());
    } catch (_) {
      return null;
    }
  }
}
