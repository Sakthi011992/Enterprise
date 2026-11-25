import 'package:dio/dio.dart';

/// A failed admin API call, turned into something a person can act on.
///
/// The backend answers errors as `{ statusCode, message, code?, details? }` (plan 1.5).
/// Friendly wording for each known `code` lives here, so every admin screen
/// says the same thing for the same failure.
class AdminApiError implements Exception {
  const AdminApiError({this.status, this.code, required this.message, this.details});

  final int? status;
  final String? code;
  final String message;
  final Map<String, dynamic>? details;

  factory AdminApiError.from(Object error) {
    if (error is AdminApiError) return error;
    if (error is DioException) {
      final body = error.response?.data;
      String? code;
      String? message;
      Map<String, dynamic>? details;
      if (body is Map) {
        code = body['code'] as String?;
        final raw = body['message'];
        message = raw is List ? raw.join(', ') : raw?.toString();
        final d = body['details'];
        if (d is Map) details = Map<String, dynamic>.from(d);
      }
      if (error.response == null) code ??= 'NETWORK';
      return AdminApiError(
        status: error.response?.statusCode,
        code: code,
        message: message ?? error.message ?? 'Request failed',
        details: details,
      );
    }
    return AdminApiError(message: error.toString());
  }

  /// The sentence to show a person. Unknown codes fall back to the server message.
  String get friendly {
    switch (code) {
      case 'NETWORK':
        return "Can't reach the server. Check your connection and try again.";
      case 'PERSONA_SYSTEM':
        return "The Admin persona is built in and can't be changed or deleted.";
      case 'PERSONA_IN_USE':
        return 'Users are still assigned to this persona. Move them to another persona first.';
      case 'LIMIT_NOT_SUPPORTED':
        return "This permission doesn't take a limit.";
      case 'PIN_TOO_SIMPLE':
        return 'That PIN is too easy to guess. Choose another 4-digit PIN.';
      case 'PIN_LOCKED':
        return 'This PIN is locked after too many wrong tries. Try again in a few minutes.';
    }
    if (status == 403) return "You don't have permission to do that.";
    return message;
  }
}

/// Reads a list from a response that is either a bare array or `{ data: [...] }`.
List<Map<String, dynamic>> listFrom(dynamic body) {
  final raw = body is Map ? body['data'] : body;
  return (raw as List).cast<Map<String, dynamic>>();
}
