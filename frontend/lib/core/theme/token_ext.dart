import 'package:flutter/material.dart';

/// Density of a region of the UI. Sets the default control height.
enum AppDensity { compact, comfortable, pos }

/// Control height step: 36 / 44 / 52 px by default.
enum AppControlSize { sm, md, lg }

/// Sets the density for everything below it. Without one, widgets use
/// [AppDensity.comfortable].
class DensityScope extends InheritedWidget {
  const DensityScope({super.key, required this.density, required super.child});

  final AppDensity density;

  static AppDensity? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DensityScope>()?.density;

  @override
  bool updateShouldNotify(DensityScope oldWidget) => oldWidget.density != density;
}

/// Tokens that sit outside the v1 contract in `ThemeTokens`. They are kept here
/// so `ThemeTokens.fromJson` stays unchanged and stored themes still parse.
/// Values are fixed defaults from the Components board, resolved by brightness.
@immutable
class ExtTokens {
  const ExtTokens({
    required this.successSubtle,
    required this.onSuccessSubtle,
    required this.warningSubtle,
    required this.onWarningSubtle,
    required this.dangerSubtle,
    required this.onDangerSubtle,
    required this.neutralSubtle,
    required this.onNeutralSubtle,
    this.controlSm = 36,
    this.controlMd = 44,
    this.controlLg = 52,
    this.density = AppDensity.comfortable,
  });

  final Color successSubtle;
  final Color onSuccessSubtle;
  final Color warningSubtle;
  final Color onWarningSubtle;
  final Color dangerSubtle;
  final Color onDangerSubtle;
  final Color neutralSubtle;
  final Color onNeutralSubtle;

  final double controlSm;
  final double controlMd;
  final double controlLg;

  final AppDensity density;

  /// Light or dark values for [brightness] at the given [density].
  factory ExtTokens.forBrightness(
    Brightness brightness, {
    AppDensity density = AppDensity.comfortable,
  }) {
    if (brightness == Brightness.dark) {
      return ExtTokens(
        successSubtle: const Color(0xFF052E16),
        onSuccessSubtle: const Color(0xFF86EFAC),
        warningSubtle: const Color(0xFF422006),
        onWarningSubtle: const Color(0xFFFDE68A),
        dangerSubtle: const Color(0xFF450A0A),
        onDangerSubtle: const Color(0xFFFCA5A5),
        neutralSubtle: const Color(0xFF27272A),
        onNeutralSubtle: const Color(0xFFE4E4E7),
        density: density,
      );
    }
    return ExtTokens(
      successSubtle: const Color(0xFFDCFCE7),
      onSuccessSubtle: const Color(0xFF14532D),
      warningSubtle: const Color(0xFFFEF3C7),
      onWarningSubtle: const Color(0xFF713F12),
      dangerSubtle: const Color(0xFFFEE2E2),
      onDangerSubtle: const Color(0xFF7F1D1D),
      neutralSubtle: const Color(0xFFE4E4E7),
      onNeutralSubtle: const Color(0xFF27272A),
      density: density,
    );
  }

  double controlHeight(AppControlSize size) => switch (size) {
        AppControlSize.sm => controlSm,
        AppControlSize.md => controlMd,
        AppControlSize.lg => controlLg,
      };

  /// comfortable → md, compact → sm, pos → lg.
  AppControlSize get defaultControlSize => switch (density) {
        AppDensity.compact => AppControlSize.sm,
        AppDensity.comfortable => AppControlSize.md,
        AppDensity.pos => AppControlSize.lg,
      };
}

/// `context.ext` resolves brightness from the nearest [Theme] and density from
/// the nearest [DensityScope].
extension ExtTokenContext on BuildContext {
  ExtTokens get ext => ExtTokens.forBrightness(
        Theme.of(this).brightness,
        density: DensityScope.maybeOf(this) ?? AppDensity.comfortable,
      );
}
