import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/permission_keys.dart';
import '../auth/permissions.dart';
import '../auth/session_controller.dart';
import 'app_feature.dart';

/// Legacy feature → the persona permission that now decides access (PLAN section 4, item 4).
/// Persona permissions are the source of truth; features are kept for old callers.
const _featurePermissions = <AppFeature, String>{
  AppFeature.dashboard: Perm.reportsView,
  AppFeature.products: Perm.menuEdit,
  AppFeature.tax: Perm.adminSettings,
  AppFeature.users: Perm.adminUsers,
  AppFeature.orders: Perm.salesOrdersTake,
  AppFeature.appearance: Perm.adminThemes,
  AppFeature.localisation: Perm.adminSettings,
  AppFeature.settings: Perm.adminSettings,
  AppFeature.kioskAdmin: Perm.adminSettings,
  AppFeature.branding: Perm.adminSettings,
};

/// The features the current session can use, derived from its permissions.
/// Empty when signed out. @deprecated: use `can(ref, Perm.x)` in new code.
final userFeaturesProvider = Provider<Set<AppFeature>>((ref) {
  final session = ref.watch(sessionProvider.select((s) => s.session));
  if (session == null) return const {};
  return {
    for (final entry in _featurePermissions.entries)
      if (canOf(session, entry.value)) entry.key,
  };
});

/// Returns true if the current user can access [feature].
final featureProvider = Provider.family<bool, AppFeature>((ref, feature) {
  return ref.watch(userFeaturesProvider).contains(feature);
});
