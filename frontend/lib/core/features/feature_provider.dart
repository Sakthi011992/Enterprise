import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/presentation/auth_controller.dart';
import 'app_feature.dart';

/// The set of features the current user has been granted.
/// ADMIN users always have all features regardless of grants.
final userFeaturesProvider = Provider<Set<AppFeature>>((ref) {
  final auth = ref.watch(authControllerProvider);
  if (!auth.isLoggedIn) return const {};
  if (auth.isAdmin) return AppFeature.values.toSet();
  return auth.features;
});

/// Returns true if the current user can access [feature].
final featureProvider = Provider.family<bool, AppFeature>((ref, feature) {
  return ref.watch(userFeaturesProvider).contains(feature);
});
