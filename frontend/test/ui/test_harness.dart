import 'package:flutter/material.dart';
import 'package:pos_billing/core/theme/app_theme.dart';
import 'package:pos_billing/core/theme/theme_tokens.dart';
import 'package:pos_billing/core/ui/ui.dart';

// Test-only copy of the bootstrap token literals. theme_providers.dart keeps
// its copy private, so the tests carry their own. Values match it exactly.

const _typography = {
  'fontFamily': {'display': 'Inter', 'body': 'Inter', 'mono': 'RobotoMono'},
  'scale': {
    'display': {'size': 32, 'weight': 700, 'height': 1.2, 'letterSpacing': -0.5},
    'title': {'size': 22, 'weight': 600, 'height': 1.3, 'letterSpacing': 0},
    'body': {'size': 15, 'weight': 400, 'height': 1.45, 'letterSpacing': 0},
    'label': {'size': 13, 'weight': 500, 'height': 1.3, 'letterSpacing': 0.2},
    'caption': {'size': 11, 'weight': 400, 'height': 1.3, 'letterSpacing': 0.4},
    'mono': {'size': 14, 'weight': 400, 'height': 1.4, 'letterSpacing': 0},
  },
};

const _scales = {
  'spacing': {'0': 0, '1': 4, '2': 8, '3': 12, '4': 16, '5': 24, '6': 32, '7': 48, '8': 64},
  'radius': {'none': 0, 'sm': 4, 'md': 8, 'lg': 16, 'pill': 999},
  'borderWidth': {'none': 0, 'hairline': 1, 'thick': 2},
  'elevation': {'none': 0, 'sm': 1, 'md': 4, 'lg': 12},
};

const _light = {
  'color': {
    'background': {
      'canvas': '#FFFFFF', 'surface': '#F4F4F5', 'raised': '#FFFFFF', 'inverse': '#18181B',
      'accent': '#3F3F46', 'danger': '#B91C1C', 'success': '#15803D', 'warning': '#A16207',
    },
    'content': {
      'primary': '#18181B', 'secondary': '#52525B', 'muted': '#A1A1AA',
      'onAccent': '#FFFFFF', 'onInverse': '#FAFAFA', 'danger': '#B91C1C',
    },
    'border': {
      'subtle': '#E4E4E7', 'default': '#D4D4D8', 'strong': '#A1A1AA',
      'accent': '#3F3F46', 'focus': '#3F3F46',
    },
  },
  ..._scales,
  'typography': _typography,
};

const _dark = {
  'color': {
    'background': {
      'canvas': '#09090B', 'surface': '#18181B', 'raised': '#27272A', 'inverse': '#FAFAFA',
      'accent': '#D4D4D8', 'danger': '#F87171', 'success': '#4ADE80', 'warning': '#FBBF24',
    },
    'content': {
      'primary': '#FAFAFA', 'secondary': '#A1A1AA', 'muted': '#71717A',
      'onAccent': '#09090B', 'onInverse': '#18181B', 'danger': '#F87171',
    },
    'border': {
      'subtle': '#27272A', 'default': '#3F3F46', 'strong': '#52525B',
      'accent': '#D4D4D8', 'focus': '#D4D4D8',
    },
  },
  ..._scales,
  'typography': _typography,
};

final AppThemeTokens testTokens = AppThemeTokens.fromJson({
  'id': 'test',
  'name': 'Test',
  'revision': 0,
  'tokens': {
    'schemaVersion': 1,
    'modes': {'light': _light, 'dark': _dark},
  },
});

/// Wraps [child] the way the app does: TokenTheme above MaterialApp, a
/// DensityScope, and a Scaffold for Material ancestors.
Widget testApp({
  required Widget child,
  Brightness brightness = Brightness.light,
  AppDensity density = AppDensity.comfortable,
}) {
  return TokenTheme(
    tokens: testTokens.forBrightness(brightness),
    child: MaterialApp(
      theme: AppTheme.from(testTokens.light, Brightness.light),
      darkTheme: AppTheme.from(testTokens.dark, Brightness.dark),
      themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: DensityScope(
        density: density,
        child: Scaffold(
          body: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
  );
}
