import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/api_error.dart';
import '../auth/session_controller.dart';
import '../providers.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    required this.isRead,
  });

  final String id;

  /// "approval" | "alert" | "device" | "stock" | "info"
  final String type;
  final String title;
  final String? body;
  final bool isRead;

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as String,
        type: (json['type'] as String?) ?? 'info',
        title: (json['title'] as String?) ?? '',
        body: json['body'] as String?,
        isRead: json['readAt'] != null,
      );
}

/// Talks to /notifications. Errors are rethrown as [ApiError].
class NotificationsRepository {
  NotificationsRepository(this._dio);

  final Dio _dio;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw ApiError.fromDio(e);
    }
  }

  /// [unreadOnly] true returns the badge data, false returns everything.
  Future<({List<AppNotification> items, int unreadCount})> list({bool unreadOnly = false}) =>
      _guard(() async {
        final res = await _dio.get('/notifications',
            queryParameters: unreadOnly ? {'unreadOnly': true} : null);
        final data = Map<String, dynamic>.from(res.data as Map);
        final items = [
          for (final e in (data['data'] as List? ?? const []))
            AppNotification.fromJson(Map<String, dynamic>.from(e as Map)),
        ];
        return (items: items, unreadCount: (data['unreadCount'] as num?)?.toInt() ?? 0);
      });

  Future<void> markRead(String id) => _guard(() async {
        await _dio.post('/notifications/$id/read');
      });

  Future<void> markAllRead() => _guard(() async {
        await _dio.post('/notifications/read-all');
      });
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepository(ref.watch(dioProvider)),
);

class NotificationsState {
  const NotificationsState({this.unreadCount = 0});

  final int unreadCount;
}

/// Polls the unread count every 60 seconds while signed in.
class NotificationsController extends StateNotifier<NotificationsState> {
  NotificationsController(this._ref) : super(const NotificationsState()) {
    refresh();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => refresh());
  }

  final Ref _ref;
  Timer? _timer;

  NotificationsRepository get _repo => _ref.read(notificationsRepositoryProvider);

  Future<void> refresh() async {
    if (_ref.read(sessionProvider).session == null) return;
    try {
      final result = await _repo.list(unreadOnly: true);
      state = NotificationsState(unreadCount: result.unreadCount);
    } catch (_) {
      // Keep the last known count; the bell just stays as it was.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final notificationsProvider =
    StateNotifierProvider<NotificationsController, NotificationsState>(
  (ref) => NotificationsController(ref),
);

/// Full list for the panel (read and unread). Invalidate after changes.
final notificationListProvider =
    FutureProvider.autoDispose<List<AppNotification>>((ref) async {
  final result = await ref.watch(notificationsRepositoryProvider).list();
  return result.items;
});
