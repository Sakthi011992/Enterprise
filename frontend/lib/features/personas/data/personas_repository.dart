import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_billing/core/providers.dart';

import 'admin_api.dart';
import 'persona_models.dart';

final personasRepositoryProvider = Provider<PersonasRepository>(
  (ref) => PersonasRepository(ref.watch(dioProvider)),
);

class PersonasRepository {
  PersonasRepository(this._dio);
  final Dio _dio;

  Future<List<CatalogEntry>> catalog() async {
    final res = await _dio.get('/permissions/catalog');
    return listFrom(res.data).map(CatalogEntry.fromJson).toList();
  }

  Future<List<Persona>> list() async {
    final res = await _dio.get('/personas');
    return listFrom(res.data).map(Persona.fromJson).toList();
  }

  Future<Persona> create({required String name, String? copyFromId}) async {
    final res = await _dio.post('/personas', data: {
      'name': name,
      if (copyFromId != null) 'copyFromId': copyFromId,
    });
    return Persona.fromJson(res.data as Map<String, dynamic>);
  }

  /// `body` holds any of name, description, homeRoute, loginMethod (PATCH is partial).
  Future<Persona> update(String id, Map<String, dynamic> body) async {
    final res = await _dio.patch('/personas/$id', data: body);
    return Persona.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> delete(String id) => _dio.delete('/personas/$id');

  Future<List<PersonaGrant>> permissions(String id) async {
    final res = await _dio.get('/personas/$id/permissions');
    return listFrom(res.data).map(PersonaGrant.fromJson).toList();
  }

  /// Replaces the persona's matrix. Send every catalog key, not only the changed ones.
  Future<void> savePermissions(String id, List<PersonaGrant> items) =>
      _dio.put('/personas/$id/permissions', data: {
        'items': items.map((g) => g.toJson()).toList(),
      });
}

/// Persona list alone, for selects in other admin screens.
final personaListProvider = FutureProvider.autoDispose<List<Persona>>(
  (ref) => ref.watch(personasRepositoryProvider).list(),
);

/// Catalog, personas and every persona's matrix, loaded together.
final personaMatrixProvider = FutureProvider.autoDispose<PersonaMatrixData>((ref) async {
  final repo = ref.watch(personasRepositoryProvider);
  final catalog = await repo.catalog();
  final personas = await repo.list();
  final perPersona = await Future.wait(personas.map((p) => repo.permissions(p.id)));
  final grants = <String, Map<String, PersonaGrant>>{
    for (var i = 0; i < personas.length; i++)
      personas[i].id: {for (final g in perPersona[i]) g.key: g},
  };
  return PersonaMatrixData(personas: personas, catalog: catalog, grants: grants);
});
