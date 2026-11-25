import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_billing/core/features/app_feature.dart';
import 'package:pos_billing/core/providers.dart';
import 'package:pos_billing/features/personas/data/admin_api.dart';

class OutletAssignment {
  const OutletAssignment({
    required this.outletId,
    required this.outletName,
    required this.personaId,
    required this.personaName,
    required this.isDefault,
  });

  final String outletId;
  final String outletName;
  final String personaId;
  final String personaName;
  final bool isDefault;

  factory OutletAssignment.fromJson(Map<String, dynamic> json) => OutletAssignment(
        outletId: json['outletId'] as String,
        outletName: (json['outletName'] as String?) ?? '',
        personaId: json['personaId'] as String,
        personaName: (json['personaName'] as String?) ?? '',
        isDefault: json['isDefault'] == true,
      );
}

/// One row of the PUT /users/:id/outlets body.
class OutletAssignmentInput {
  const OutletAssignmentInput({required this.outletId, required this.personaId, required this.isDefault});

  final String outletId;
  final String personaId;
  final bool isDefault;

  Map<String, dynamic> toJson() => {'outletId': outletId, 'personaId': personaId, 'isDefault': isDefault};
}

class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    this.displayName,
    this.email,
    this.phone,
    required this.isActive,
    required this.hasPin,
    required this.outlets,
  });

  final String id;
  final String username;
  final String? displayName;
  final String? email;
  final String? phone;
  final bool isActive;
  final bool hasPin;
  final List<OutletAssignment> outlets;

  /// Display name when set, otherwise the username.
  String get label {
    final name = displayName?.trim();
    return (name == null || name.isEmpty) ? username : name;
  }

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        username: json['username'] as String,
        displayName: json['displayName'] as String?,
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        isActive: json['isActive'] != false,
        hasPin: json['hasPin'] == true,
        outlets: ((json['outlets'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(OutletAssignment.fromJson)
            .toList(),
      );
}

final usersRepositoryProvider = Provider<UsersRepository>(
  (ref) => UsersRepository(ref.watch(dioProvider)),
);

class UsersRepository {
  UsersRepository(this._dio);
  final Dio _dio;

  /// Up to 100 users. The screen filters them locally.
  Future<List<AppUser>> list() async {
    final res = await _dio.get('/users', queryParameters: {'limit': 100});
    return listFrom(res.data).map(AppUser.fromJson).toList();
  }

  /// Returns the new user's id.
  Future<String> create(Map<String, dynamic> body) async {
    final res = await _dio.post('/users', data: body);
    return (res.data as Map<String, dynamic>)['id'] as String;
  }

  /// PATCH is partial: send only the fields that change.
  Future<void> update(String id, Map<String, dynamic> body) => _dio.patch('/users/$id', data: body);

  /// Replaces the user's outlet assignments. Exactly one must be the default.
  Future<void> setOutlets(String id, List<OutletAssignmentInput> items) =>
      _dio.put('/users/$id/outlets', data: {'items': items.map((i) => i.toJson()).toList()});

  Future<void> setPin(String id, String pin) => _dio.patch('/users/$id/pin', data: {'pin': pin});

  Future<void> resetPassword(String id, String newPassword) =>
      _dio.patch('/users/$id/reset-password', data: {'newPassword': newPassword});

  /// Legacy feature grants (deprecated in Phase 1, removed in Phase 2).
  Future<Set<AppFeature>> features(String id) async {
    final res = await _dio.get('/users/$id/features');
    final wire = (res.data as List).cast<String>();
    return wire.map(AppFeature.fromWire).whereType<AppFeature>().toSet();
  }

  /// Legacy feature grants: replaces the whole set.
  Future<void> setFeatures(String id, Set<AppFeature> features) => _dio.put(
        '/users/$id/features',
        data: {'features': features.map((f) => f.wireValue).toList()},
      );
}

final usersListProvider = FutureProvider.autoDispose<List<AppUser>>(
  (ref) => ref.watch(usersRepositoryProvider).list(),
);

final userFeaturesProvider = FutureProvider.autoDispose.family<Set<AppFeature>, String>(
  (ref, id) => ref.watch(usersRepositoryProvider).features(id),
);
