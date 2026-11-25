import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';

final menuRepositoryProvider = Provider<MenuRepository>(
  (ref) => MenuRepository(ref.watch(dioProvider)),
);

double _money(Object? v) => double.tryParse(v?.toString() ?? '') ?? 0;

String _moneyText(double v) => v.toStringAsFixed(2);

List<String> _ids(Object? raw) => raw is List ? raw.map((e) => e.toString()).toList() : const [];

class MenuCategory {
  const MenuCategory({
    required this.id,
    required this.name,
    this.color,
    this.sortOrder = 0,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String? color;
  final int sortOrder;
  final bool isActive;

  factory MenuCategory.fromJson(Map j) => MenuCategory(
        id: j['id'] as String,
        name: j['name'] as String,
        color: j['color'] as String?,
        sortOrder: (j['sortOrder'] as num?)?.toInt() ?? 0,
        isActive: j['isActive'] as bool? ?? true,
      );
}

class MenuVariant {
  const MenuVariant({
    this.id,
    required this.name,
    required this.price,
    this.isDefault = false,
    this.sortOrder = 0,
  });

  final String? id;
  final String name;
  final double price;
  final bool isDefault;
  final int sortOrder;

  factory MenuVariant.fromJson(Map j) => MenuVariant(
        id: j['id'] as String?,
        name: j['name'] as String,
        price: _money(j['price']),
        isDefault: j['isDefault'] as bool? ?? false,
        sortOrder: (j['sortOrder'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson(int index) => {
        if (id != null) 'id': id,
        'name': name,
        'price': _moneyText(price),
        'isDefault': isDefault,
        'sortOrder': index,
      };
}

class MenuProduct {
  const MenuProduct({
    required this.id,
    required this.name,
    this.description,
    this.categoryId,
    this.taxClassId,
    required this.price,
    this.is86 = false,
    this.isActive = true,
    this.variants = const [],
    this.modifierGroupIds = const [],
  });

  final String id;
  final String name;
  final String? description;
  final String? categoryId;
  final String? taxClassId;
  final double price;
  final bool is86;
  final bool isActive;
  final List<MenuVariant> variants;
  final List<String> modifierGroupIds;

  factory MenuProduct.fromJson(Map j) => MenuProduct(
        id: j['id'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        categoryId: j['categoryId'] as String?,
        taxClassId: j['taxClassId'] as String?,
        price: _money(j['price']),
        is86: j['is86'] as bool? ?? false,
        isActive: j['isActive'] as bool? ?? true,
        variants: [
          for (final v in (j['variants'] as List? ?? const [])) MenuVariant.fromJson(v as Map),
        ],
        modifierGroupIds: _ids(j['modifierGroupIds']),
      );
}

class ModifierOption {
  const ModifierOption({
    this.id,
    required this.name,
    this.priceDelta = 0,
    this.stockItemId,
    this.stockQty,
  });

  final String? id;
  final String name;
  final double priceDelta;

  /// Stock item deducted when this option is picked (Phase 3). Null for none.
  final String? stockItemId;

  /// Base units deducted per serving of this option.
  final double? stockQty;

  factory ModifierOption.fromJson(Map j) => ModifierOption(
        id: j['id'] as String?,
        name: j['name'] as String,
        priceDelta: _money(j['priceDelta']),
        stockItemId: j['stockItemId'] as String?,
        stockQty: double.tryParse(j['stockQty']?.toString() ?? ''),
      );

  Map<String, dynamic> toJson(int index) => {
        if (id != null) 'id': id,
        'name': name,
        'priceDelta': _moneyText(priceDelta),
        'sortOrder': index,
        // Sent even when empty, so clearing a stock link saves.
        'stockItemId': stockItemId,
        'stockQty': stockQty,
      };
}

class ModifierGroup {
  const ModifierGroup({
    required this.id,
    required this.name,
    this.minSelect = 0,
    this.maxSelect = 1,
    this.options = const [],
    this.usedBy = 0,
  });

  final String id;
  final String name;
  final int minSelect;
  final int maxSelect;
  final List<ModifierOption> options;
  final int usedBy;

  factory ModifierGroup.fromJson(Map j) => ModifierGroup(
        id: j['id'] as String,
        name: j['name'] as String,
        minSelect: (j['minSelect'] as num?)?.toInt() ?? 0,
        maxSelect: (j['maxSelect'] as num?)?.toInt() ?? 1,
        options: [
          for (final o in (j['options'] as List? ?? const [])) ModifierOption.fromJson(o as Map),
        ],
        usedBy: (j['usedBy'] as num?)?.toInt() ?? 0,
      );
}

class ComboItem {
  const ComboItem({required this.productId, this.quantity = 1, this.swapAllowed = false});

  final String productId;
  final int quantity;
  final bool swapAllowed;

  factory ComboItem.fromJson(Map j) => ComboItem(
        productId: j['productId'] as String,
        quantity: (j['quantity'] as num?)?.toInt() ?? 1,
        swapAllowed: j['swapAllowed'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'quantity': quantity,
        'swapAllowed': swapAllowed,
      };
}

class Combo {
  const Combo({
    required this.id,
    required this.name,
    required this.price,
    this.isActive = true,
    this.items = const [],
  });

  final String id;
  final String name;
  final double price;
  final bool isActive;
  final List<ComboItem> items;

  factory Combo.fromJson(Map j) => Combo(
        id: j['id'] as String,
        name: j['name'] as String,
        price: _money(j['price']),
        isActive: j['isActive'] as bool? ?? true,
        items: [
          for (final i in (j['items'] as List? ?? const [])) ComboItem.fromJson(i as Map),
        ],
      );
}

class PriceRule {
  const PriceRule({
    required this.id,
    required this.name,
    required this.percentOff,
    this.categoryIds = const [],
    this.productIds = const [],
    this.isActive = true,
    this.activeNow = false,
    this.endsAt,
  });

  final String id;
  final String name;
  final double percentOff;
  final List<String> categoryIds;
  final List<String> productIds;
  final bool isActive;
  final bool activeNow;
  final DateTime? endsAt;

  factory PriceRule.fromJson(Map j) => PriceRule(
        id: j['id'] as String,
        name: j['name'] as String,
        percentOff: _money(j['percentOff']),
        categoryIds: _ids(j['categoryIds']),
        productIds: _ids(j['productIds']),
        isActive: j['isActive'] as bool? ?? true,
        activeNow: j['activeNow'] as bool? ?? false,
        endsAt: j['endsAt'] == null ? null : DateTime.tryParse(j['endsAt'].toString()),
      );
}

/// Menu editors: categories, products, modifier groups, combos and price rules.
class MenuRepository {
  MenuRepository(this._dio);
  final Dio _dio;

  static List<Map> _rows(dynamic body) {
    final raw = body is Map ? body['data'] : body;
    return (raw as List).cast<Map>();
  }

  // Categories
  Future<List<MenuCategory>> categories() async {
    final res = await _dio.get('/categories');
    return _rows(res.data).map(MenuCategory.fromJson).toList();
  }

  Future<void> createCategory(Map<String, dynamic> body) => _dio.post('/categories', data: body);

  Future<void> updateCategory(String id, Map<String, dynamic> body) =>
      _dio.patch('/categories/$id', data: body);

  /// Soft delete. Throws 409 CATEGORY_IN_USE while active products use it.
  Future<void> deleteCategory(String id) => _dio.delete('/categories/$id');

  // Products
  Future<List<MenuProduct>> products() async {
    // The list endpoint is paged with at most 100 rows per page.
    final out = <MenuProduct>[];
    for (var page = 1; page <= 20; page++) {
      final res = await _dio.get('/products', queryParameters: {'limit': 100, 'page': page});
      out.addAll(_rows(res.data).map(MenuProduct.fromJson));
      final meta = res.data is Map ? (res.data as Map)['meta'] : null;
      final totalPages = meta is Map ? (meta['totalPages'] as num?)?.toInt() ?? 1 : 1;
      if (page >= totalPages) break;
    }
    return out;
  }

  Future<MenuProduct> product(String id) async {
    final res = await _dio.get('/products/$id');
    return MenuProduct.fromJson(res.data as Map);
  }

  Future<void> updateProduct(String id, Map<String, dynamic> body) =>
      _dio.patch('/products/$id', data: body);

  /// Replaces the variant list. Exactly one item must be the default.
  Future<void> setVariants(String id, List<MenuVariant> variants) => _dio.put(
        '/products/$id/variants',
        data: {
          'items': [for (var i = 0; i < variants.length; i++) variants[i].toJson(i)],
        },
      );

  Future<void> setModifierGroups(String id, List<String> groupIds) =>
      _dio.put('/products/$id/modifier-groups', data: {'groupIds': groupIds});

  Future<void> set86(String id, bool is86) => _dio.post('/products/$id/86', data: {'is86': is86});

  // Modifier groups
  Future<List<ModifierGroup>> modifierGroups() async {
    final res = await _dio.get('/modifier-groups');
    return _rows(res.data).map(ModifierGroup.fromJson).toList();
  }

  Future<ModifierGroup> createModifierGroup(Map<String, dynamic> body) async {
    final res = await _dio.post('/modifier-groups', data: body);
    return ModifierGroup.fromJson(res.data as Map);
  }

  /// Body carries the full option list; the options it names replace the old ones.
  Future<void> updateModifierGroup(String id, Map<String, dynamic> body) =>
      _dio.put('/modifier-groups/$id', data: body);

  Future<void> deleteModifierGroup(String id) => _dio.delete('/modifier-groups/$id');

  // Combos
  Future<List<Combo>> combos() async {
    final res = await _dio.get('/combos');
    return _rows(res.data).map(Combo.fromJson).toList();
  }

  Future<void> createCombo(Map<String, dynamic> body) => _dio.post('/combos', data: body);

  Future<void> updateCombo(String id, Map<String, dynamic> body) => _dio.put('/combos/$id', data: body);

  Future<void> deleteCombo(String id) => _dio.delete('/combos/$id');

  // Price rules (happy hours)
  Future<List<PriceRule>> priceRules() async {
    final res = await _dio.get('/price-rules');
    return _rows(res.data).map(PriceRule.fromJson).toList();
  }

  Future<void> createPriceRule(Map<String, dynamic> body) => _dio.post('/price-rules', data: body);

  Future<void> updatePriceRule(String id, Map<String, dynamic> body) =>
      _dio.patch('/price-rules/$id', data: body);

  Future<void> deletePriceRule(String id) => _dio.delete('/price-rules/$id');
}

final menuCategoriesProvider = FutureProvider<List<MenuCategory>>(
  (ref) => ref.watch(menuRepositoryProvider).categories(),
);

final menuProductsProvider = FutureProvider<List<MenuProduct>>(
  (ref) => ref.watch(menuRepositoryProvider).products(),
);

final menuModifierGroupsProvider = FutureProvider<List<ModifierGroup>>(
  (ref) => ref.watch(menuRepositoryProvider).modifierGroups(),
);

final menuCombosProvider = FutureProvider<List<Combo>>(
  (ref) => ref.watch(menuRepositoryProvider).combos(),
);

final menuPriceRulesProvider = FutureProvider<List<PriceRule>>(
  (ref) => ref.watch(menuRepositoryProvider).priceRules(),
);
