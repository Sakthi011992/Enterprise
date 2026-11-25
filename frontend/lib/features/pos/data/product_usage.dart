import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

/// Counts product taps on this device, for the Favourites rail (top 12 by
/// recent use). Stored in Hive as productId -> count string.
class ProductUsage {
  ProductUsage(this._box);

  static const boxName = 'pos_usage';
  static const favouriteCount = 12;

  final Box<String> _box;

  void record(String productId) {
    final current = int.tryParse(_box.get(productId) ?? '') ?? 0;
    _box.put(productId, '${current + 1}');
  }

  int countOf(String productId) => int.tryParse(_box.get(productId) ?? '') ?? 0;

  /// Product ids with the highest counts, most used first. Ties keep the
  /// order they were stored in.
  List<String> topIds([int limit = favouriteCount]) {
    final entries = [
      for (final key in _box.keys.cast<String>())
        if (countOf(key) > 0) MapEntry(key, countOf(key)),
    ];
    entries.sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in entries.take(limit)) e.key];
  }
}

/// Opens the usage box once. Open after `SessionStore.init()` has run.
final productUsageProvider = FutureProvider.autoDispose<ProductUsage>((ref) async {
  final box = Hive.isBoxOpen(ProductUsage.boxName)
      ? Hive.box<String>(ProductUsage.boxName)
      : await Hive.openBox<String>(ProductUsage.boxName);
  return ProductUsage(box);
});
