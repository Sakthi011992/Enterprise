import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../features/themes/data/theme_repository.dart';
import 'app_theme.dart';
import 'theme_tokens.dart';

/// Wire this to the app's existing Dio + Hive providers.
final themeRepositoryProvider = Provider<ThemeRepository>((ref) {
  throw UnimplementedError(
    'Override themeRepositoryProvider in main.dart with the app Dio client and '
    'an opened Hive box, e.g.:\n'
    "  themeRepositoryProvider.overrideWithValue(\n"
    "    ThemeRepository(dio: ref.read(dioProvider), cacheBox: await Hive.openBox('theme')),\n"
    "  )",
  );
});

/// Persists the user's manual light/dark choice across launches, independent of
/// the admin-assigned brand theme (which supplies the tokens, not the mode).
class ThemeModeStore {
  ThemeModeStore(this._box);
  final Box _box;
  static const _key = 'mode';

  /// Seeds from the device's current brightness the first time the app ever
  /// runs; after that the user's own choice always wins.
  ThemeMode read() {
    final raw = _box.get(_key);
    if (raw == 'light') return ThemeMode.light;
    if (raw == 'dark') return ThemeMode.dark;
    final platformBrightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return platformBrightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light;
  }

  Future<void> write(ThemeMode mode) => _box.put(_key, mode.name);
}

final themeModeStoreProvider = Provider<ThemeModeStore>((ref) {
  throw UnimplementedError(
    'Override themeModeStoreProvider in main.dart with an opened Hive box, e.g.:\n'
    "  themeModeStoreProvider.overrideWithValue(\n"
    "    ThemeModeStore(await Hive.openBox('theme_mode')),\n"
    "  )",
  );
});

class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._store) : super(_store.read());
  final ThemeModeStore _store;

  void toggle() => set(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);

  void set(ThemeMode mode) {
    state = mode;
    _store.write(mode);
  }
}

/// The user's chosen appearance — always resolved to light or dark, never
/// "system", so this is the single source of truth [ThemeScope] and
/// [MaterialApp.themeMode] both read from.
final themeModeProvider = StateNotifierProvider<ThemeModeController, ThemeMode>(
  (ref) => ThemeModeController(ref.watch(themeModeStoreProvider)),
);

@immutable
class ThemeState {
  const ThemeState({this.tokens, this.isRefreshing = false, this.error});

  /// Null only before the first successful load on a fresh install.
  final AppThemeTokens? tokens;
  final bool isRefreshing;
  final Object? error;

  ThemeState copyWith({AppThemeTokens? tokens, bool? isRefreshing, Object? error}) =>
      ThemeState(
        tokens: tokens ?? this.tokens,
        isRefreshing: isRefreshing ?? this.isRefreshing,
        error: error,
      );
}

/// Owns the active token set.
///
/// Load order is deliberate: cache first so the UI paints immediately with the
/// right branding, then a network refresh in the background. A failed refresh
/// never clears a working theme — the till keeps running.
class ThemeController extends StateNotifier<ThemeState> {
  ThemeController(this._repo) : super(const ThemeState()) {
    _bootstrap();
  }

  final ThemeRepository _repo;

  void _bootstrap() {
    final cached = _repo.readCached();
    if (cached != null) state = state.copyWith(tokens: cached);
    refresh();
  }

  Future<void> refresh() async {
    state = state.copyWith(isRefreshing: true, error: null);
    try {
      final fetched = await _repo.fetchActive();
      state = ThemeState(
        // null means "nothing changed" (304) — keep what we have.
        tokens: fetched ?? state.tokens,
        isRefreshing: false,
      );
    } catch (err) {
      state = state.copyWith(isRefreshing: false, error: err);
    }
  }

  /// Called by the admin editor to preview unsaved tokens without persisting.
  void previewOverride(AppThemeTokens preview) {
    state = state.copyWith(tokens: preview);
  }

  /// Drops any preview and re-pulls the assigned theme.
  Future<void> cancelPreview() => refresh();
}

final themeControllerProvider =
    StateNotifierProvider<ThemeController, ThemeState>(
  (ref) => ThemeController(ref.watch(themeRepositoryProvider)),
);

/// Fallback used only on a fresh install with no network. Neutral greys — enough
/// to render a login screen legibly until real tokens arrive.
final _bootstrapTokens = AppThemeTokens.fromJson(const {
  'id': 'bootstrap',
  'name': 'Bootstrap',
  'revision': 0,
  'tokens': {
    'schemaVersion': 1,
    'modes': {
      'light': _bootstrapLight,
      'dark': _bootstrapDark,
    },
  },
});

/// Wraps the app, supplying both Flutter's ThemeData and the raw token tree.
class ThemeScope extends ConsumerWidget {
  const ThemeScope({super.key, required this.builder});

  final Widget Function(BuildContext context, ThemeData light, ThemeData dark) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(themeControllerProvider).tokens ?? _bootstrapTokens;
    final mode = ref.watch(themeModeProvider);
    final brightness = mode == ThemeMode.dark ? Brightness.dark : Brightness.light;

    return TokenTheme(
      tokens: tokens.forBrightness(brightness),
      child: Builder(
        builder: (inner) => builder(
          inner,
          AppTheme.from(tokens.light, Brightness.light),
          AppTheme.from(tokens.dark, Brightness.dark),
        ),
      ),
    );
  }
}

// --- bootstrap token literals -----------------------------------------------

// Default theme: "Ink & Emerald" (docs/ui-design/ink-emerald). Six text sizes; Manrope for
// headings and large numbers, Inter for everything else.
const _typography = {
  'fontFamily': {'display': 'Manrope', 'body': 'Inter', 'mono': 'Roboto Mono'},
  'scale': {
    'display': {'size': 28, 'weight': 700, 'height': 1.2, 'letterSpacing': -0.5},
    'title': {'size': 16, 'weight': 700, 'height': 1.35, 'letterSpacing': -0.1},
    'body': {'size': 14, 'weight': 400, 'height': 1.45, 'letterSpacing': 0},
    'label': {'size': 13, 'weight': 500, 'height': 1.35, 'letterSpacing': 0},
    'caption': {'size': 12, 'weight': 500, 'height': 1.35, 'letterSpacing': 0},
    'mono': {'size': 13, 'weight': 400, 'height': 1.4, 'letterSpacing': 0},
  },
};

const _scales = {
  'spacing': {'0': 0, '1': 4, '2': 8, '3': 12, '4': 16, '5': 24, '6': 32, '7': 48, '8': 64},
  // 6 chips · 10 buttons and inputs · 16 cards.
  'radius': {'none': 0, 'sm': 6, 'md': 10, 'lg': 16, 'pill': 999},
  'borderWidth': {'none': 0, 'hairline': 1, 'thick': 2},
  'elevation': {'none': 0, 'sm': 1, 'md': 4, 'lg': 12},
};

// Light: ink text on a soft neutral page, white cards, one emerald accent.
// Every text colour passes 4.5:1 on white and on the page ground.
const _bootstrapLight = {
  'color': {
    'background': {
      'canvas': '#F5F6F8', 'surface': '#FFFFFF', 'raised': '#FFFFFF', 'inverse': '#0B1220',
      'accent': '#0E7C66', 'danger': '#D92D20', 'success': '#067647', 'warning': '#B54708',
    },
    'content': {
      'primary': '#101828', 'secondary': '#475467', 'muted': '#667085',
      'onAccent': '#FFFFFF', 'onInverse': '#F2F4F7', 'danger': '#B42318',
    },
    'border': {
      'subtle': '#F2F4F7', 'default': '#E4E7EC', 'strong': '#D0D5DD',
      'accent': '#0E7C66', 'focus': '#0E7C66',
    },
  },
  ..._scales,
  'typography': _typography,
};

// Dark (POS, KDS, TV): deep ink layers, brighter emerald with dark text on it.
const _bootstrapDark = {
  'color': {
    'background': {
      'canvas': '#0A0F1A', 'surface': '#0E1524', 'raised': '#151E30', 'inverse': '#F2F4F7',
      'accent': '#2FB896', 'danger': '#F97066', 'success': '#32D583', 'warning': '#FDB022',
    },
    'content': {
      'primary': '#F2F4F7', 'secondary': '#A3ADC2', 'muted': '#8A94A6',
      'onAccent': '#04231C', 'onInverse': '#0B1220', 'danger': '#F97066',
    },
    'border': {
      'subtle': '#1C263A', 'default': '#233049', 'strong': '#2B3A57',
      'accent': '#2FB896', 'focus': '#2FB896',
    },
  },
  ..._scales,
  'typography': _typography,
};
