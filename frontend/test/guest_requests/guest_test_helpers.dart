import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_billing/core/auth/permission_keys.dart';
import 'package:pos_billing/core/auth/session.dart';
import 'package:pos_billing/core/providers.dart';
import 'package:pos_billing/core/storage/session_store.dart';
import 'package:pos_billing/features/guest_requests/data/guest_requests_providers.dart';
import 'package:pos_billing/features/guest_requests/data/guest_requests_repository.dart';
import 'package:pos_billing/features/guest_requests/data/mock_guest_requests_repository.dart';

import '../ui/test_harness.dart';

/// A session store that never touches Hive.
class FakeSessionStore extends SessionStore {
  FakeSessionStore(this._session);
  final Session? _session;

  @override
  String? get accessToken => _session == null ? null : 'token';

  @override
  Map<String, dynamic>? get session =>
      _session == null ? null : jsonDecode(jsonEncode(_session.toJson())) as Map<String, dynamic>;
}

PermissionGrant grant(AccessLevel level) => PermissionGrant(level: level);

Session testSession({
  String persona = 'waiter',
  String userId = 'u-1',
  Map<String, PermissionGrant>? permissions,
}) =>
    Session(
      user: SessionUser(id: userId, username: 'tester', displayName: 'Tester'),
      tenant: const NamedRef(id: 't', name: 'Pegs & Bottles'),
      outlet: const OutletRef(id: 'o', name: 'Main outlet', code: 'MAIN'),
      persona: PersonaRef(id: 'p', key: persona, name: persona, homeRoute: '/floor'),
      permissions: permissions ??
          {
            Perm.salesOrdersTake: grant(AccessLevel.edit),
            Perm.guestsOrdersConfirm: grant(AccessLevel.edit),
            Perm.kdsBump: grant(AccessLevel.view),
          },
      outlets: const [],
      role: 'USER',
    );

/// The app's theme and density plus provider overrides for the guest screens.
/// Live sync (socket + polling) is turned off.
Widget guestTestApp({
  required Widget child,
  required GuestRequestsRepository repo,
  Session? session,
}) {
  final s = session ?? testSession();
  return ProviderScope(
    overrides: [
      sessionStoreProvider.overrideWithValue(FakeSessionStore(s)),
      guestRequestsRepositoryProvider.overrideWithValue(repo),
      guestLiveProvider.overrideWith((ref) {}),
    ],
    child: testApp(child: child),
  );
}

MockGuestRequestsRepository demoRepo() => MockGuestRequestsRepository(currentUserId: 'u-1');
