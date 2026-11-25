/// Session model: the JSON returned by every login / select / switch / pin
/// login and by GET /auth/me (PLAN 1.5). Tokens are not part of this model.
enum AccessLevel {
  none(0, 'NONE'),
  view(1, 'VIEW'),
  request(2, 'REQUEST'),
  limited(3, 'LIMITED'),
  approve(4, 'APPROVE'),
  edit(5, 'EDIT');

  const AccessLevel(this.rank, this.wire);

  final int rank;

  /// Value used on the wire.
  final String wire;

  /// True when this level is at least [min] in the catalog order.
  bool atLeast(AccessLevel min) => rank >= min.rank;

  static AccessLevel fromWire(Object? value) {
    for (final level in values) {
      if (level.wire == value) return level;
    }
    return AccessLevel.none;
  }
}

class SessionUser {
  const SessionUser({
    required this.id,
    required this.username,
    this.displayName,
    this.email,
  });

  final String id;
  final String username;
  final String? displayName;
  final String? email;

  /// Name to show in the UI.
  String get label => (displayName != null && displayName!.isNotEmpty) ? displayName! : username;

  factory SessionUser.fromJson(Map<String, dynamic> json) => SessionUser(
        id: json['id'] as String,
        username: json['username'] as String,
        displayName: json['displayName'] as String?,
        email: json['email'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'displayName': displayName,
        'email': email,
      };
}

class NamedRef {
  const NamedRef({required this.id, required this.name});

  final String id;
  final String name;

  factory NamedRef.fromJson(Map<String, dynamic> json) =>
      NamedRef(id: json['id'] as String, name: json['name'] as String);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

class OutletRef {
  const OutletRef({required this.id, required this.name, required this.code});

  final String id;
  final String name;
  final String code;

  factory OutletRef.fromJson(Map<String, dynamic> json) => OutletRef(
        id: json['id'] as String,
        name: json['name'] as String,
        code: json['code'] as String,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'code': code};
}

class PersonaRef {
  const PersonaRef({
    required this.id,
    required this.key,
    required this.name,
    required this.homeRoute,
  });

  final String id;
  final String key;
  final String name;
  final String homeRoute;

  factory PersonaRef.fromJson(Map<String, dynamic> json) => PersonaRef(
        id: json['id'] as String,
        key: json['key'] as String,
        name: json['name'] as String,
        homeRoute: (json['homeRoute'] as String?) ?? '/dashboard',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'key': key,
        'name': name,
        'homeRoute': homeRoute,
      };
}

/// Persona as shown inside the outlets list (no id in the contract).
class OutletPersona {
  const OutletPersona({required this.key, required this.name});

  final String key;
  final String name;

  factory OutletPersona.fromJson(Map<String, dynamic> json) =>
      OutletPersona(key: json['key'] as String, name: json['name'] as String);

  Map<String, dynamic> toJson() => {'key': key, 'name': name};
}

class OutletAccess {
  const OutletAccess({
    required this.id,
    required this.name,
    required this.code,
    required this.persona,
    required this.isDefault,
  });

  final String id;
  final String name;
  final String code;
  final OutletPersona persona;
  final bool isDefault;

  factory OutletAccess.fromJson(Map<String, dynamic> json) => OutletAccess(
        id: json['id'] as String,
        name: json['name'] as String,
        code: json['code'] as String,
        persona: OutletPersona.fromJson(json['persona'] as Map<String, dynamic>),
        isDefault: (json['isDefault'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'code': code,
        'persona': persona.toJson(),
        'isDefault': isDefault,
      };
}

class PermissionGrant {
  const PermissionGrant({required this.level, this.limit});

  final AccessLevel level;

  /// Percent or INR, depending on the catalog limit unit. Null when none.
  final num? limit;

  factory PermissionGrant.fromJson(Map<String, dynamic> json) => PermissionGrant(
        level: AccessLevel.fromWire(json['level']),
        limit: json['limit'] as num?,
      );

  Map<String, dynamic> toJson() => {'level': level.wire, 'limit': limit};
}

class Session {
  const Session({
    required this.user,
    required this.tenant,
    required this.outlet,
    required this.persona,
    required this.permissions,
    required this.outlets,
    required this.role,
  });

  final SessionUser user;
  final NamedRef tenant;
  final OutletRef outlet;
  final PersonaRef persona;
  final Map<String, PermissionGrant> permissions;
  final List<OutletAccess> outlets;

  /// Legacy: "ADMIN" or "USER".
  final String role;

  /// Level for [key]; NONE when the key is absent.
  AccessLevel levelOf(String key) => permissions[key]?.level ?? AccessLevel.none;

  bool get isAdmin => role == 'ADMIN';

  factory Session.fromJson(Map<String, dynamic> json) {
    final rawPermissions = (json['permissions'] as Map?) ?? const {};
    final rawOutlets = (json['outlets'] as List?) ?? const [];
    return Session(
      user: SessionUser.fromJson(json['user'] as Map<String, dynamic>),
      tenant: NamedRef.fromJson(json['tenant'] as Map<String, dynamic>),
      outlet: OutletRef.fromJson(json['outlet'] as Map<String, dynamic>),
      persona: PersonaRef.fromJson(json['persona'] as Map<String, dynamic>),
      permissions: {
        for (final entry in rawPermissions.entries)
          entry.key as String: PermissionGrant.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          ),
      },
      outlets: [
        for (final o in rawOutlets)
          OutletAccess.fromJson(Map<String, dynamic>.from(o as Map)),
      ],
      role: (json['role'] as String?) ?? 'USER',
    );
  }

  Map<String, dynamic> toJson() => {
        'user': user.toJson(),
        'tenant': tenant.toJson(),
        'outlet': outlet.toJson(),
        'persona': persona.toJson(),
        'permissions': {
          for (final entry in permissions.entries) entry.key: entry.value.toJson(),
        },
        'outlets': [for (final o in outlets) o.toJson()],
        'role': role,
      };
}

/// Returned by POST /auth/login when the user must choose an outlet first.
class OutletChoice {
  const OutletChoice({required this.selectionToken, required this.outlets});

  final String selectionToken;
  final List<OutletAccess> outlets;
}
