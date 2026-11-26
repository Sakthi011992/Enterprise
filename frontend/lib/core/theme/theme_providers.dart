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

/// Fallback used when no theme is assigned or the network is down on a fresh
/// install: the default "Pegs & Bottles" theme.
final _bootstrapTokens = AppThemeTokens.fromJson(const {
  'id': 'bootstrap',
  'name': 'Bootstrap',
  'revision': 0,
  'tokens': {
    'schemaVersion': 2,
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

// Default theme: "Pegs & Bottles" (backend/prisma/themes/pegs-and-bottles.json), taken from the
// pub's interior. DM Serif Display for headings and large numbers, Work Sans for everything else.
const _typography = {
  'fontFamily': {'display': 'DM Serif Display', 'body': 'Work Sans', 'mono': 'JetBrains Mono'},
  'scale': {
    'display': {'size': 30, 'weight': 400, 'height': 1.15, 'letterSpacing': -0.2},
    'title': {'size': 17, 'weight': 600, 'height': 1.3, 'letterSpacing': -0.1},
    'body': {'size': 14, 'weight': 400, 'height': 1.45, 'letterSpacing': 0},
    'label': {'size': 13, 'weight': 600, 'height': 1.35, 'letterSpacing': 0},
    'caption': {'size': 12, 'weight': 500, 'height': 1.35, 'letterSpacing': 0.1},
    'mono': {'size': 13, 'weight': 500, 'height': 1.4, 'letterSpacing': 0},
  },
};

const _scales = {
  'spacing': {'0': 0, '1': 4, '2': 8, '3': 12, '4': 16, '5': 24, '6': 32, '7': 48, '8': 64},
  // 6 chips · 10 buttons and inputs · 14 cards.
  'radius': {'none': 0, 'sm': 6, 'md': 10, 'lg': 14, 'pill': 999},
  'borderWidth': {'none': 0, 'hairline': 1, 'thick': 2},
  'elevation': {'none': 0, 'sm': 1, 'md': 4, 'lg': 12},
};

// Light: warm stone page, bottle-green header and sidebar, lacquer-red accent.
// Every text colour passes 4.5:1 on the cards and on the page.
const _bootstrapLight = {
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
  ..._scales,
  'typography': _typography,
};

// Dark: a bottle-green room, green leather cards, near-black header, brass accent.
const _bootstrapDark = {
  'color': {
    'background': {
      'canvas': '#0D1C15', 'surface': '#14271E', 'raised': '#1B3227', 'inverse': '#F3ECDD', 'header': '#08130E',
      'accent': '#E2B055', 'danger': '#FF8A7A', 'success': '#3DD68C', 'warning': '#F0A84A',
    },
    'content': {
      'primary': '#F3ECDD', 'secondary': '#C3BBA8', 'muted': '#A49C8A',
      'onAccent': '#1F1606', 'onInverse': '#1A1714', 'onHeader': '#F3ECDD', 'danger': '#FF8A7A',
    },
    'border': {
      'subtle': '#1B3227', 'default': '#244033', 'strong': '#2F5242',
      'accent': '#E2B055', 'focus': '#E2B055',
    },
  },
  ..._scales,
  'typography': _typography,
};
