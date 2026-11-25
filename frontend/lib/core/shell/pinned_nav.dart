import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../storage/session_store.dart';

/// Most nav items a user can pin to the top of the side nav.
const maxPinnedNav = 5;

/// Pinned nav ids, persisted in [SessionStore].
class PinnedNavController extends StateNotifier<List<String>> {
  PinnedNavController(this._store) : super(_store.pinnedNavIds);

  final SessionStore _store;

  /// Pins or unpins [id]. Returns false when the limit is already reached.
  bool toggle(String id) {
    if (state.contains(id)) {
      _set(state.where((e) => e != id).toList());
      return true;
    }
    if (state.length >= maxPinnedNav) return false;
    _set([...state, id]);
    return true;
  }

  void _set(List<String> ids) {
    state = ids;
    _store.setPinnedNavIds(ids);
  }
}

final pinnedNavProvider = StateNotifierProvider<PinnedNavController, List<String>>(
  (ref) => PinnedNavController(ref.watch(sessionStoreProvider)),
);
