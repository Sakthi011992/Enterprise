import 'package:dio/dio.dart';

/// Error from the API, parsed from the filter shape in PLAN 1.5:
/// `{ statusCode, message, error, code?, details?, path, timestamp }`.
/// `status` is 0 when no response arrived (offline, timeout, DNS).
class ApiError implements Exception {
  const ApiError({
    required this.status,
    this.code,
    required this.message,
    this.details,
  });

  final int status;
  final String? code;
  final String message;
  final Map<String, dynamic>? details;

  bool get isNetwork => status == 0;
  bool get isUnauthorized => status == 401;

  /// Integer detail such as `attemptsLeft`, or null.
  int? intDetail(String key) {
    final v = details?[key];
    return v is num ? v.toInt() : null;
  }

  /// String detail such as `lockedUntil`, or null.
  String? stringDetail(String key) {
    final v = details?[key];
    return v is String ? v : null;
  }

  factory ApiError.fromDio(DioException e) {
    final response = e.response;
    if (response == null) {
      return const ApiError(
        status: 0,
        message: "Couldn't reach the server. Check your connection.",
      );
    }
    final status = response.statusCode ?? 0;
    final data = response.data;
    if (data is Map) {
      final rawMessage = data['message'];
      final message = rawMessage is List
          ? rawMessage.join(', ')
          : (rawMessage is String ? rawMessage : 'Request failed ($status).');
      final rawDetails = data['details'];
      return ApiError(
        status: status,
        code: data['code'] as String?,
        message: message,
        details: rawDetails is Map ? Map<String, dynamic>.from(rawDetails) : null,
      );
    }
    return ApiError(status: status, message: 'Request failed ($status).');
  }

  /// Converts anything thrown by Dio into an [ApiError]; other errors pass as
  /// a status-0 error.
  factory ApiError.from(Object error) {
    if (error is ApiError) return error;
    if (error is DioException) return ApiError.fromDio(error);
    return ApiError(status: 0, message: error.toString());
  }

  @override
  String toString() => 'ApiError($status, ${code ?? '-'}): $message';
}
