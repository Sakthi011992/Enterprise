import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_providers.dart';
import '../../../core/theme/theme_tokens.dart';
import '../../../core/ui/ui.dart';

/// Light tokens of the outlet's assigned theme, or null before one has loaded.
/// Tests override it.
final guestLightTokensProvider = Provider<ThemeTokens?>((ref) {
  try {
    return ref.watch(themeControllerProvider).tokens?.light;
  } catch (_) {
    return null; // theme repository not wired (tests, or a bare ProviderScope)
  }
});

/// The guest app is light-only in v1 (Q-12). This forces the light token set
/// and a light [ThemeData] below it, whatever the staff app's mode is, and
/// sets the POS density (52 px touch targets).
class GuestThemeScope extends ConsumerWidget {
  const GuestThemeScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ambient = Theme.of(context).brightness == Brightness.light
        ? _maybeTokens(context)
        : null;
    final tokens = ref.watch(guestLightTokensProvider) ?? ambient ?? pegsLightTokens;
    return TokenTheme(
      tokens: tokens,
      child: Theme(
        data: AppTheme.from(tokens, Brightness.light),
        child: DensityScope(density: AppDensity.pos, child: child),
      ),
    );
  }
}

ThemeTokens? _maybeTokens(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<TokenTheme>()?.tokens;

/// Fallback when no theme has loaded and the staff app is in dark mode: the
/// light half of the default "Pegs & Bottles" theme
/// (backend/prisma/themes/pegs-and-bottles.json), same values as the bootstrap
/// tokens in core/theme/theme_providers.dart.
final ThemeTokens pegsLightTokens = ThemeTokens.fromJson(const {
  'color': {
    'background': {
      'canvas': '#ECE7DE', 'surface': '#FFFDF9', 'raised': '#FFFDF9', 'inverse': '#16291F', 'header': '#1F3D2E',
      'accent': '#B3301D', 'danger': '#B42318', 'success': '#1F6B45', 'warning': '#A35F00',
    },
    'content': {
      'primary': '#1A1714', 'secondary': '#554D44', 'muted': '#675E55',
      'onAccent': '#FFFFFF', 'onInverse': '#F4EFE6', 'onHeader': '#F4EFE6', 'danger': '#B42318',
    },
    'border': {
      'subtle': '#EFE9DF', 'default': '#E0D8CC', 'strong': '#CCC1B2',
      'accent': '#B3301D', 'focus': '#B3301D',
    },
  },
  'spacing': {'0': 0, '1': 4, '2': 8, '3': 12, '4': 16, '5': 24, '6': 32, '7': 48, '8': 64},
  'radius': {'none': 0, 'sm': 6, 'md': 10, 'lg': 14, 'pill': 999},
  'borderWidth': {'none': 0, 'hairline': 1, 'thick': 2},
  'elevation': {'none': 0, 'sm': 1, 'md': 4, 'lg': 12},
  'typography': {
    'fontFamily': {'display': 'DM Serif Display', 'body': 'Work Sans', 'mono': 'JetBrains Mono'},
    'scale': {
      'display': {'size': 30, 'weight': 400, 'height': 1.15, 'letterSpacing': -0.2},
      'title': {'size': 17, 'weight': 600, 'height': 1.3, 'letterSpacing': -0.1},
      'body': {'size': 14, 'weight': 400, 'height': 1.45, 'letterSpacing': 0},
      'label': {'size': 13, 'weight': 600, 'height': 1.35, 'letterSpacing': 0},
      'caption': {'size': 12, 'weight': 500, 'height': 1.35, 'letterSpacing': 0.1},
      'mono': {'size': 13, 'weight': 500, 'height': 1.4, 'letterSpacing': 0},
    },
  },
}, 'pegs.light');
