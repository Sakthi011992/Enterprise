import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'theme_tokens.dart';

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
  bool updateShouldNotify(DensityScope oldWidget) =>
      oldWidget.density != density;
}

/// Tokens that sit outside the v1 contract in `ThemeTokens`. They are kept here
/// so `ThemeTokens.fromJson` stays unchanged and stored themes still parse.
/// Status colours are fixed; the accent tints, neutral fills, shadows and the
/// navigation colours are derived from the active theme's own tokens.
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
    required this.infoSubtle,
    required this.onInfoSubtle,
    required this.accentSubtle,
    required this.onAccentSubtle,
    required this.accentSubtleBorder,
    required this.brassSubtle,
    required this.onBrassSubtle,
    required this.subtleFill,
    required this.selectedRow,
    required this.dangerBorder,
    required this.focusRing,
    required this.cardShadow,
    required this.raisedShadow,
    this.navBackground = const Color(0xFF0B1220),
    this.navActive = const Color(0xFF16213A),
    this.navSubActive = const Color(0xFF111A2B),
    this.navDivider = const Color(0xFF1F2A3D),
    this.navForeground = const Color(0xFFC7CED9),
    this.navForegroundActive = const Color(0xFFFFFFFF),
    this.navMuted = const Color(0xFF8A94A6),
    this.navAccent = const Color(0xFF2FB896),
    this.statusRed = const Color(0xFFD92D20),
    this.statusAmber = const Color(0xFFF79009),
    this.statusGreen = const Color(0xFF12B76A),
    this.statusBlue = const Color(0xFF2E90FA),
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
  final Color infoSubtle;
  final Color onInfoSubtle;

  /// Selected chips, active filters, highlighted rows: soft emerald fill, its text and border.
  final Color accentSubtle;
  final Color onAccentSubtle;
  final Color accentSubtleBorder;

  /// Happy hour, premium and "Pro" tags.
  final Color brassSubtle;
  final Color onBrassSubtle;

  /// Table header rows, search fields, segmented-control tracks.
  final Color subtleFill;

  /// Background of a selected table row (pair with a 3 px accent edge).
  final Color selectedRow;

  /// Border of an input in error, and the soft ring drawn around a focused or invalid input.
  final Color dangerBorder;
  final Color focusRing;

  /// Card and raised-surface shadows (dialogs, drawers, hero cards).
  final List<BoxShadow> cardShadow;
  final List<BoxShadow> raisedShadow;

  /// The ink navigation rail and sidebar, the same in light and dark mode.
  final Color navBackground;
  final Color navActive;
  final Color navSubActive;
  final Color navDivider;
  final Color navForeground;
  final Color navForegroundActive;
  final Color navMuted;
  final Color navAccent;

  /// Status dots and small indicators (live, alerts, occupancy).
  final Color statusRed;
  final Color statusAmber;
  final Color statusGreen;
  final Color statusBlue;

  final double controlSm;
  final double controlMd;
  final double controlLg;

  final AppDensity density;

  /// Light or dark values for [brightness] at the given [density].
  factory ExtTokens.forBrightness(
    Brightness brightness, {
    AppDensity density = AppDensity.comfortable,
  }) {
    // "Ink & Emerald": soft fills with strong text, every pair at 4.5:1 or better.
    if (brightness == Brightness.dark) {
      return ExtTokens(
        successSubtle: const Color(0xFF0E2A1F),
        onSuccessSubtle: const Color(0xFF6CE9A6),
        warningSubtle: const Color(0xFF2A2213),
        onWarningSubtle: const Color(0xFFFEC84B),
        dangerSubtle: const Color(0xFF2A1517),
        onDangerSubtle: const Color(0xFFFDA29B),
        neutralSubtle: const Color(0xFF1A2438),
        onNeutralSubtle: const Color(0xFFC7CED9),
        infoSubtle: const Color(0xFF13203A),
        onInfoSubtle: const Color(0xFF84CAFF),
        accentSubtle: const Color(0xFF13241F),
        onAccentSubtle: const Color(0xFF5FD0B2),
        accentSubtleBorder: const Color(0xFF1F4D41),
        brassSubtle: const Color(0xFF2A2213),
        onBrassSubtle: const Color(0xFFF5C46B),
        subtleFill: const Color(0xFF111A2B),
        selectedRow: const Color(0xFF13241F),
        dangerBorder: const Color(0xFFF97066),
        focusRing: const Color(0x552FB896),
        cardShadow: const [],
        raisedShadow: const [
          BoxShadow(
              color: Color(0x66000000),
              blurRadius: 24,
              offset: Offset(0, 8),
              spreadRadius: -8),
        ],
        density: density,
      );
    }
    return ExtTokens(
      successSubtle: const Color(0xFFECFDF3),
      onSuccessSubtle: const Color(0xFF067647),
      warningSubtle: const Color(0xFFFFFAEB),
      onWarningSubtle: const Color(0xFFB54708),
      dangerSubtle: const Color(0xFFFEF3F2),
      onDangerSubtle: const Color(0xFFB42318),
      neutralSubtle: const Color(0xFFF2F4F7),
      onNeutralSubtle: const Color(0xFF344054),
      infoSubtle: const Color(0xFFEFF8FF),
      onInfoSubtle: const Color(0xFF175CD3),
      accentSubtle: const Color(0xFFE7F4F0),
      onAccentSubtle: const Color(0xFF0A5F4E),
      accentSubtleBorder: const Color(0xFFA6E3D3),
      brassSubtle: const Color(0xFFFBF3E4),
      onBrassSubtle: const Color(0xFF8A5A12),
      subtleFill: const Color(0xFFF9FAFB),
      selectedRow: const Color(0xFFF3FAF8),
      dangerBorder: const Color(0xFFFDA29B),
      focusRing: const Color(0x330E7C66),
      cardShadow: const [
        BoxShadow(
            color: Color(0x0A101828), blurRadius: 2, offset: Offset(0, 1)),
      ],
      raisedShadow: const [
        BoxShadow(
            color: Color(0x0A101828), blurRadius: 2, offset: Offset(0, 1)),
        BoxShadow(
            color: Color(0x14101828),
            blurRadius: 24,
            offset: Offset(0, 8),
            spreadRadius: -8),
      ],
      density: density,
    );
  }

  /// Same as [forBrightness], but the accent tints, neutral fills, shadows and navigation
  /// colours follow [tokens], so every stored theme looks like itself and not like emerald.
  factory ExtTokens.fromTokens(
    ThemeTokens tokens,
    Brightness brightness, {
    AppDensity density = AppDensity.comfortable,
  }) {
    final base = ExtTokens.forBrightness(brightness, density: density);
    final dark = brightness == Brightness.dark;
    final bg = tokens.color.background;
    final fg = tokens.color.content;
    final accent = bg.accent;
    final surface = bg.surface;
    Color mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

    final navBg = dark ? bg.canvas : bg.inverse;
    final navDark = navBg.computeLuminance() < 0.4;
    final onNav = navDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
    final accentHsl = HSLColor.fromColor(accent);
    final navAccent = navDark && accentHsl.lightness < 0.5
        ? accentHsl
            .withLightness(0.5)
            .withSaturation(accentHsl.saturation.clamp(0.0, 0.65))
            .toColor()
        : accent;

    final shadow = fg.primary;
    return base.copyWith(
      accentSubtle: mix(surface, accent, dark ? 0.16 : 0.10),
      onAccentSubtle: dark
          ? mix(accent, const Color(0xFFFFFFFF), 0.25)
          : mix(accent, const Color(0xFF000000), 0.25),
      accentSubtleBorder: mix(surface, accent, dark ? 0.32 : 0.35),
      selectedRow: mix(surface, accent, dark ? 0.09 : 0.05),
      focusRing: accent.withValues(alpha: dark ? 0.33 : 0.20),
      subtleFill: mix(surface, fg.primary, 0.025),
      neutralSubtle: mix(surface, fg.primary, dark ? 0.10 : 0.06),
      onNeutralSubtle: fg.secondary,
      cardShadow: dark
          ? const []
          : [
              BoxShadow(
                  color: shadow.withValues(alpha: 0.04),
                  blurRadius: 2,
                  offset: const Offset(0, 1)),
            ],
      raisedShadow: dark
          ? base.raisedShadow
          : [
              BoxShadow(
                  color: shadow.withValues(alpha: 0.04),
                  blurRadius: 2,
                  offset: const Offset(0, 1)),
              BoxShadow(
                  color: shadow.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                  spreadRadius: -8),
            ],
      navBackground: navBg,
      navActive: mix(navBg, onNav, 0.07),
      navSubActive: mix(navBg, onNav, 0.035),
      navDivider: mix(navBg, onNav, 0.10),
      navForeground: mix(navBg, onNav, 0.78),
      navForegroundActive: onNav,
      navMuted: mix(navBg, onNav, 0.50),
      navAccent: navAccent,
    );
  }

  ExtTokens copyWith({
    Color? neutralSubtle,
    Color? onNeutralSubtle,
    Color? accentSubtle,
    Color? onAccentSubtle,
    Color? accentSubtleBorder,
    Color? subtleFill,
    Color? selectedRow,
    Color? focusRing,
    List<BoxShadow>? cardShadow,
    List<BoxShadow>? raisedShadow,
    Color? navBackground,
    Color? navActive,
    Color? navSubActive,
    Color? navDivider,
    Color? navForeground,
    Color? navForegroundActive,
    Color? navMuted,
    Color? navAccent,
  }) =>
      ExtTokens(
        successSubtle: successSubtle,
        onSuccessSubtle: onSuccessSubtle,
        warningSubtle: warningSubtle,
        onWarningSubtle: onWarningSubtle,
        dangerSubtle: dangerSubtle,
        onDangerSubtle: onDangerSubtle,
        neutralSubtle: neutralSubtle ?? this.neutralSubtle,
        onNeutralSubtle: onNeutralSubtle ?? this.onNeutralSubtle,
        infoSubtle: infoSubtle,
        onInfoSubtle: onInfoSubtle,
        accentSubtle: accentSubtle ?? this.accentSubtle,
        onAccentSubtle: onAccentSubtle ?? this.onAccentSubtle,
        accentSubtleBorder: accentSubtleBorder ?? this.accentSubtleBorder,
        brassSubtle: brassSubtle,
        onBrassSubtle: onBrassSubtle,
        subtleFill: subtleFill ?? this.subtleFill,
        selectedRow: selectedRow ?? this.selectedRow,
        dangerBorder: dangerBorder,
        focusRing: focusRing ?? this.focusRing,
        cardShadow: cardShadow ?? this.cardShadow,
        raisedShadow: raisedShadow ?? this.raisedShadow,
        navBackground: navBackground ?? this.navBackground,
        navActive: navActive ?? this.navActive,
        navSubActive: navSubActive ?? this.navSubActive,
        navDivider: navDivider ?? this.navDivider,
        navForeground: navForeground ?? this.navForeground,
        navForegroundActive: navForegroundActive ?? this.navForegroundActive,
        navMuted: navMuted ?? this.navMuted,
        navAccent: navAccent ?? this.navAccent,
        statusRed: statusRed,
        statusAmber: statusAmber,
        statusGreen: statusGreen,
        statusBlue: statusBlue,
        controlSm: controlSm,
        controlMd: controlMd,
        controlLg: controlLg,
        density: density,
      );

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
  ExtTokens get ext {
    final brightness = Theme.of(this).brightness;
    final density = DensityScope.maybeOf(this) ?? AppDensity.comfortable;
    final tokens = dependOnInheritedWidgetOfExactType<TokenTheme>()?.tokens;
    return tokens == null
        ? ExtTokens.forBrightness(brightness, density: density)
        : ExtTokens.fromTokens(tokens, brightness, density: density);
  }
}
