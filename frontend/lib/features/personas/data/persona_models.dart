import 'package:flutter/foundation.dart';
import 'package:pos_billing/core/auth/session.dart';

enum LoginMethod { password, pin }

LoginMethod loginMethodFromApi(String? raw) =>
    raw == 'PIN' ? LoginMethod.pin : LoginMethod.password;

String loginMethodToApi(LoginMethod method) => method == LoginMethod.pin ? 'PIN' : 'PASSWORD';

String loginMethodLabel(LoginMethod method) =>
    method == LoginMethod.pin ? 'PIN on a shared tablet' : 'Password';

/// API level string ("EDIT") to the frontend enum (AccessLevel.edit).
AccessLevel accessLevelFromApi(String? raw) {
  final name = (raw ?? 'NONE').toLowerCase();
  return AccessLevel.values.firstWhere((level) => level.name == name, orElse: () => AccessLevel.none);
}

String accessLevelToApi(AccessLevel level) => level.name.toUpperCase();

String levelLabel(AccessLevel level) {
  return switch (level) {
    AccessLevel.none => 'None',
    AccessLevel.view => 'View',
    AccessLevel.request => 'Request',
    AccessLevel.limited => 'Limited',
    AccessLevel.approve => 'Approve',
    AccessLevel.edit => 'Edit',
  };
}

/// Whole numbers print without decimals: 30 not 30.0.
String formatNumber(num value) => value % 1 == 0 ? value.toInt().toString() : value.toString();

num? _parseLimit(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return raw;
  return num.tryParse(raw.toString());
}

class Persona {
  const Persona({
    required this.id,
    required this.key,
    required this.name,
    this.description,
    required this.homeRoute,
    required this.loginMethod,
    required this.isSystem,
    required this.userCount,
  });

  final String id;
  final String key;
  final String name;
  final String? description;
  final String homeRoute;
  final LoginMethod loginMethod;
  final bool isSystem;
  final int userCount;

  factory Persona.fromJson(Map<String, dynamic> json) => Persona(
        id: json['id'] as String,
        key: json['key'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        homeRoute: (json['homeRoute'] as String?) ?? '/dashboard',
        loginMethod: loginMethodFromApi(json['loginMethod'] as String?),
        isSystem: json['isSystem'] == true,
        userCount: (json['userCount'] as num?)?.toInt() ?? 0,
      );
}

/// One row of the permission catalog (`GET /permissions/catalog`).
class CatalogEntry {
  const CatalogEntry({
    required this.key,
    required this.group,
    required this.label,
    this.description,
    this.limitUnit,
    required this.sortOrder,
  });

  final String key;
  final String group;
  final String label;
  final String? description;

  /// "percent" | "inr" | null.
  final String? limitUnit;
  final int sortOrder;

  factory CatalogEntry.fromJson(Map<String, dynamic> json) => CatalogEntry(
        key: json['key'] as String,
        group: json['group'] as String,
        label: json['label'] as String,
        description: json['description'] as String?,
        limitUnit: json['limitUnit'] as String?,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      );
}

/// What one persona may do for one permission key.
@immutable
class PersonaGrant {
  const PersonaGrant({required this.key, required this.level, this.limit});

  final String key;
  final AccessLevel level;
  final num? limit;

  bool sameAs(PersonaGrant other) => level == other.level && limit == other.limit;

  factory PersonaGrant.fromJson(Map<String, dynamic> json) => PersonaGrant(
        key: json['key'] as String,
        level: accessLevelFromApi(json['level'] as String?),
        limit: _parseLimit(json['limit']),
      );

  /// A limit only travels with the LIMITED level; the backend rejects it elsewhere.
  Map<String, dynamic> toJson() => {
        'key': key,
        'level': accessLevelToApi(level),
        'limit': level == AccessLevel.limited ? limit : null,
      };
}

/// Everything the matrix needs, loaded in one go.
class PersonaMatrixData {
  const PersonaMatrixData({required this.personas, required this.catalog, required this.grants});

  final List<Persona> personas;
  final List<CatalogEntry> catalog;

  /// personaId -> permission key -> grant. A missing key means NONE.
  final Map<String, Map<String, PersonaGrant>> grants;
}

/// Looks up a grant in a personaId -> key -> grant map; missing means NONE.
PersonaGrant grantFor(Map<String, Map<String, PersonaGrant>> source, String personaId, String key) =>
    source[personaId]?[key] ?? PersonaGrant(key: key, level: AccessLevel.none);

/// Catalog rows grouped by their group name, in sortOrder.
List<MapEntry<String, List<CatalogEntry>>> groupCatalog(List<CatalogEntry> catalog) {
  final sorted = [...catalog]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  final groups = <String, List<CatalogEntry>>{};
  for (final entry in sorted) {
    groups.putIfAbsent(entry.group, () => []).add(entry);
  }
  return groups.entries.toList();
}

/// Text for a matrix cell, e.g. "Limited ≤ 10%" or "Edit".
String permissionLabel(PersonaGrant grant, CatalogEntry? entry) {
  if (grant.level != AccessLevel.limited) return levelLabel(grant.level);
  final limit = grant.limit;
  if (limit == null) return 'Limited';
  final amount = formatNumber(limit);
  return switch (entry?.limitUnit) {
    'percent' => 'Limited ≤ $amount%',
    'inr' => 'Limited ≤ ₹$amount',
    _ => 'Limited',
  };
}

/// Screens a persona can land on after sign-in (persona.homeRoute).
const homeRouteOptions = ['/dashboard', '/pos', '/orders', '/menu', '/stock-count', '/my-shifts'];

String homeRouteLabel(String route) {
  return switch (route) {
    '/dashboard' => 'Dashboard',
    '/pos' => 'POS billing',
    '/orders' => 'Orders',
    '/menu' => 'Menu & products',
    '/stock-count' => 'Stock count',
    '/my-shifts' => 'My shifts',
    _ => route,
  };
}
