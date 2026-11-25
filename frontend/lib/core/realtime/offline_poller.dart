import 'dart:async';

import 'package:flutter/foundation.dart';

/// Runs [refresh] every [interval], but only while [connected] is false. A
/// screen uses it as the fallback when the realtime socket is down. While the
/// socket is up, events drive the refresh and this poller does nothing.
class OfflinePoller {
  OfflinePoller({
    required this.connected,
    required this.interval,
    required this.refresh,
  });

  final ValueListenable<bool> connected;
  final Duration interval;
  final Future<void> Function() refresh;

  Timer? _timer;

  bool get running => _timer != null;

  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(interval, (_) => tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// One poll step. Returns true when [refresh] ran (socket down).
  Future<bool> tick() async {
    if (connected.value) return false;
    await refresh();
    return true;
  }
}
