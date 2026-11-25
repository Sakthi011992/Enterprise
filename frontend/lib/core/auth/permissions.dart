import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'session.dart';
import 'session_controller.dart';

/// Pure check used by widgets, the router and tests. A missing session or a
/// missing key counts as NONE.
bool canOf(Session? session, String key, [AccessLevel min = AccessLevel.view]) {
  if (session == null) return false;
  return session.levelOf(key).atLeast(min);
}

/// Riverpod form of [canOf], keyed by (permission key, minimum level).
final canProvider = Provider.family<bool, (String, AccessLevel)>((ref, arg) {
  final session = ref.watch(sessionProvider.select((s) => s.session));
  return canOf(session, arg.$1, arg.$2);
});

/// Use inside `build`: `if (can(ref, Perm.menuEdit, AccessLevel.edit)) ...`.
bool can(WidgetRef ref, String key, [AccessLevel min = AccessLevel.view]) =>
    ref.watch(canProvider((key, min)));
