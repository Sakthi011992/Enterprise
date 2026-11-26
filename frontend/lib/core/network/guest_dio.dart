import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';

/// Holds the guest bearer token for the guest QR app (PLAN 2.3). It is never
/// the staff access token: guest tokens are a separate scope.
class GuestTokenHolder {
  String? token;
}

final guestTokenHolderProvider = Provider<GuestTokenHolder>((ref) => GuestTokenHolder());

/// Dio for `/guest/*`. Same base URL as the staff Dio ([AppConfig.apiBaseUrl]),
/// but it sends the guest token and never tries the staff refresh flow.
Dio createGuestDio(GuestTokenHolder holder, {String? baseUrl}) {
  final dio = Dio(BaseOptions(
    baseUrl: baseUrl ?? AppConfig.apiBaseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    final token = holder.token;
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }));
  return dio;
}

final guestDioProvider = Provider<Dio>(
  (ref) => createGuestDio(ref.watch(guestTokenHolderProvider)),
);
