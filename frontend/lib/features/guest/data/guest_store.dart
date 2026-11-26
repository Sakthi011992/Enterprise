import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// What a phone remembers about one table: the guest token and who joined.
class StoredGuest {
  const StoredGuest({
    required this.token,
    required this.participantId,
    required this.name,
    required this.phone,
    this.ageConfirmed = false,
  });

  final String token;
  final String participantId;
  final String name;
  final String phone;
  final bool ageConfirmed;

  StoredGuest copyWith({bool? ageConfirmed}) => StoredGuest(
        token: token,
        participantId: participantId,
        name: name,
        phone: phone,
        ageConfirmed: ageConfirmed ?? this.ageConfirmed,
      );

  Map<String, dynamic> toJson() => {
        'token': token,
        'participantId': participantId,
        'name': name,
        'phone': phone,
        'ageConfirmed': ageConfirmed,
      };

  static StoredGuest? fromJson(Object? raw) {
    if (raw is! String) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final token = j['token'];
      if (token is! String || token.isEmpty) return null;
      return StoredGuest(
        token: token,
        participantId: (j['participantId'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        phone: (j['phone'] ?? '').toString(),
        ageConfirmed: j['ageConfirmed'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Per-browser storage for the guest app: one random `deviceKey` and one
/// stored guest per table QR token (PLAN 2.8).
abstract class GuestStore {
  Future<String> deviceKey();
  Future<StoredGuest?> guestFor(String qrToken);
  Future<void> saveGuest(String qrToken, StoredGuest guest);
  Future<void> clearGuest(String qrToken);
}

/// 32 url-safe random characters.
String newDeviceKey([Random? random]) {
  final r = random ?? Random.secure();
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  return List.generate(32, (_) => chars[r.nextInt(chars.length)]).join();
}

/// In-memory store, for tests and the mock run.
class MemoryGuestStore implements GuestStore {
  MemoryGuestStore({String? deviceKey}) : _deviceKey = deviceKey;

  String? _deviceKey;
  final Map<String, StoredGuest> _guests = {};

  @override
  Future<String> deviceKey() async => _deviceKey ??= newDeviceKey();

  @override
  Future<StoredGuest?> guestFor(String qrToken) async => _guests[qrToken];

  @override
  Future<void> saveGuest(String qrToken, StoredGuest guest) async => _guests[qrToken] = guest;

  @override
  Future<void> clearGuest(String qrToken) async => _guests.remove(qrToken);
}

/// Hive-backed store (the app's existing storage; IndexedDB on the web), in its
/// own `guest` box so staff sign-out never touches it.
class HiveGuestStore implements GuestStore {
  static const _boxName = 'guest';
  static const _kDevice = 'deviceKey';

  Future<Box>? _opening;

  Future<Box> _box() {
    if (Hive.isBoxOpen(_boxName)) return Future.value(Hive.box(_boxName));
    return _opening ??= Hive.openBox(_boxName);
  }

  @override
  Future<String> deviceKey() async {
    final box = await _box();
    final existing = box.get(_kDevice) as String?;
    if (existing != null && existing.isNotEmpty) return existing;
    final key = newDeviceKey();
    await box.put(_kDevice, key);
    return key;
  }

  @override
  Future<StoredGuest?> guestFor(String qrToken) async =>
      StoredGuest.fromJson((await _box()).get('t:$qrToken'));

  @override
  Future<void> saveGuest(String qrToken, StoredGuest guest) async =>
      (await _box()).put('t:$qrToken', jsonEncode(guest.toJson()));

  @override
  Future<void> clearGuest(String qrToken) async => (await _box()).delete('t:$qrToken');
}

final guestStoreProvider = Provider<GuestStore>((ref) => HiveGuestStore());
