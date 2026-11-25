import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/kds_models.dart';
import '../data/kds_repository.dart';

/// `GET /kds/tickets` for one station code (`ALL`, `BAR`, `KITCHEN`, ...).
/// Invalidate to refresh.
final kdsBoardProvider = FutureProvider.autoDispose.family<KdsBoard, String>(
  (ref, station) => ref.watch(kdsRepositoryProvider).board(station: station),
);

/// `GET /kds/stations`. Invalidate to refresh.
final kdsStationsProvider = FutureProvider.autoDispose<List<KdsStation>>(
  (ref) => ref.watch(kdsRepositoryProvider).stations(),
);

/// `GET /kds/ready`. The argument is `mine`. Invalidate to refresh.
final readyItemsProvider = FutureProvider.autoDispose.family<List<ReadyItem>, bool>(
  (ref, mine) => ref.watch(kdsRepositoryProvider).ready(mine: mine),
);
