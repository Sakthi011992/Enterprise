import 'package:flutter/material.dart';

/// Display helpers for the POS. Pure Dart apart from [Color], so tests can call them.

/// Groups the integer digits the Indian way: 2034 -> 2,034, 100000 -> 1,00,000.
String groupIndian(String digits) {
  if (digits.length <= 3) return digits;
  final last3 = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${parts.join(',')},$last3';
}

/// Rupee text. Whole rupees show no paise. Non-zero paise show two decimals.
/// `alwaysPaise` forces two decimals (use it for change and payments).
String formatRupees(num value, {bool alwaysPaise = false}) {
  final negative = value < 0;
  final paise = (value.abs() * 100).round();
  final rupees = paise ~/ 100;
  final fraction = paise % 100;
  final body = groupIndian(rupees.toString());
  final text = (alwaysPaise || fraction != 0)
      ? '$body.${fraction.toString().padLeft(2, '0')}'
      : body;
  return '${negative ? '-' : ''}₹$text';
}

/// Formats an API money string (two decimals) for display.
String formatWire(String amount, {bool alwaysPaise = false}) =>
    formatRupees(num.tryParse(amount) ?? 0, alwaysPaise: alwaysPaise);

/// "8:00 pm" style clock text in the device's local time.
String formatClock(DateTime time) {
  final hour24 = time.hour;
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  final suffix = hour24 < 12 ? 'am' : 'pm';
  return '$hour12:$minute $suffix';
}

/// Parses `#RRGGBB` or `#AARRGGBB`. Returns null for anything else.
Color? parseHexColor(String? hex) {
  if (hex == null) return null;
  var value = hex.trim().replaceFirst('#', '');
  if (value.length == 6) value = 'FF$value';
  if (value.length != 8) return null;
  final parsed = int.tryParse(value, radix: 16);
  return parsed == null ? null : Color(parsed);
}

/// Parses a rupee amount typed by the user. Empty or bad input gives 0.
double parseRupeeInput(String text) {
  final cleaned = text.replaceAll(',', '').replaceAll('₹', '').trim();
  return double.tryParse(cleaned) ?? 0;
}

/// Money to the wire: two decimals.
String wireMoney(num value) => value.toStringAsFixed(2);

/// Rounds half up to paise.
double roundPaise(num value) => ((value * 100).round()) / 100;
