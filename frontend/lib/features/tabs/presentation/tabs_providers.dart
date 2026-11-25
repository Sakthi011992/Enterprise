import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/tabs_models.dart';
import '../data/tabs_repository.dart';

/// `GET /tabs?scope=today`. The argument is the bartender filter (null = all).
/// Invalidate to refresh.
final tabsPageProvider = FutureProvider.autoDispose.family<TabsPage, String?>(
  (ref, openedById) => ref.watch(tabsRepositoryProvider).tabs(openedById: openedById),
);

/// `GET /locker?status=ACTIVE`. Invalidate to refresh.
final lockersProvider = FutureProvider.autoDispose<List<LockerView>>(
  (ref) => ref.watch(tabsRepositoryProvider).lockers(status: LockerStatuses.active),
);
