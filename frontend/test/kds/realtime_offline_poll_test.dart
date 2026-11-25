import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_billing/core/realtime/offline_poller.dart';
import 'package:pos_billing/core/realtime/realtime_client.dart';

void main() {
  group('OfflinePoller', () {
    test('refreshes the repository while the socket is down', () async {
      final connected = ValueNotifier<bool>(false);
      var refreshes = 0;
      final poller = OfflinePoller(
        connected: connected,
        interval: const Duration(seconds: 5),
        refresh: () async => refreshes++,
      );

      expect(await poller.tick(), isTrue);
      expect(await poller.tick(), isTrue);
      expect(refreshes, 2);
    });

    test('does nothing while the socket is connected', () async {
      final connected = ValueNotifier<bool>(true);
      var refreshes = 0;
      final poller = OfflinePoller(
        connected: connected,
        interval: const Duration(seconds: 5),
        refresh: () async => refreshes++,
      );

      expect(await poller.tick(), isFalse);
      expect(refreshes, 0);

      // Switching the link off starts the polling without a restart.
      connected.value = false;
      expect(await poller.tick(), isTrue);
      expect(refreshes, 1);
      connected.dispose();
    });

    test('start and stop are idempotent', () {
      final connected = ValueNotifier<bool>(false);
      final poller = OfflinePoller(
        connected: connected,
        interval: const Duration(minutes: 1),
        refresh: () async {},
      );
      expect(poller.running, isFalse);
      poller
        ..start()
        ..start();
      expect(poller.running, isTrue);
      poller
        ..stop()
        ..stop();
      expect(poller.running, isFalse);
      connected.dispose();
    });
  });

  group('realtime endpoint', () {
    test('uses the API origin with the /rt namespace', () {
      expect(realtimeUrl('http://localhost:3000/api/v1'), 'http://localhost:3000/rt');
      expect(realtimeUrl('https://pos.example.in/api/v1'), 'https://pos.example.in/rt');
    });

    test('reconnect back-off doubles and stops at 30 seconds', () {
      expect(reconnectDelay(0), const Duration(seconds: 1));
      expect(reconnectDelay(1), const Duration(seconds: 2));
      expect(reconnectDelay(2), const Duration(seconds: 4));
      expect(reconnectDelay(9), const Duration(seconds: 30));
    });
  });
}
