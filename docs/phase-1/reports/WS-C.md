# WS-C report: component kit, token extension, states, translations (frontend)

Status: written, not compiled or tested (no Flutter SDK or network in this environment). Every file was reread for imports, const use and name matches against PLAN.md section 1.8.

## Files created or changed

Owned files only. Nothing outside WS-C was edited, and nothing was committed.

- `frontend/lib/core/theme/token_ext.dart`: `AppDensity`, `AppControlSize`, `DensityScope`, `ExtTokens` (subtle colours, control heights 36/44/52, density, `forBrightness`, `controlHeight`, `defaultControlSize`), and `extension ExtTokenContext on BuildContext { ExtTokens get ext; }`.
- `frontend/lib/core/ui/`:
  - `ui.dart`: barrel. Exports the kit, `token_ext.dart` and `app_theme.dart`, so callers get `context.tokens` from the barrel too.
  - `ui_style.dart`, `field_frame.dart`, `tone_bar.dart`: internal helpers, not exported.
  - `app_button.dart`: `AppButton`, `AppButtonVariant`.
  - `app_icon_button.dart`: `AppIconButton`.
  - `app_text_field.dart`: `AppTextField`.
  - `app_select.dart`: `AppSelect<T>`, `AppSelectItem<T>(value, label)`, positional as in the 1.8 table.
  - `status_tone.dart`: `StatusTone`, `ToneColors`, `toneColorsOf`.
  - `status_badge.dart`: `StatusBadge`.
  - `inline_alert.dart`: `InlineAlert`. `app_banner.dart`: `AppBanner`.
  - `app_toast.dart`: `showAppToast`.
  - `empty_state.dart`: `EmptyState`. `error_state.dart`: `ErrorState`.
  - `skeleton.dart`: `SkeletonBox`, `SkeletonList`, `DelayedSkeleton`.
  - `page_header.dart`: `PageHeader`. `app_card.dart`: `AppCard`.
  - `app_data_table.dart`: `AppDataTable<T>`, `AppColumn<T>`.
  - `confirm_dialog.dart`: `showConfirmDialog`.
  - `pin_pad.dart`: `PinPad`.
- `frontend/lib/l10n/app_en.arb` (template, 29 keys from the plan, plural and placeholder metadata), `app_ta.arb` and `app_hi.arb` (English copies, each entry marked `"x-untranslated": true`).
- `frontend/l10n.yaml`.
- `frontend/pubspec.yaml`: added `flutter_localizations: sdk: flutter` and `generate: true` under `flutter:`.
- `frontend/lib/features/dev/component_gallery_screen.dart`: `ComponentGalleryScreen`. Shows every widget in its variants and states, at three densities, in light and dark when the app's tokens are loaded (falls back to the current mode otherwise).
- `frontend/test/ui/`: `test_harness.dart` (`testApp(...)`, plus a test-only copy of the bootstrap tokens), `app_button_test.dart` (loading blocks taps, tap fires, height follows density), `pin_pad_test.dart` (completes at length then clears, backspace), `status_badge_test.dart` (each tone shows its word, dark mode), `app_data_table_test.dart` (bulk bar appears on selection).
- `docs/phase-1/reports/WS-C.md`: this file.

`ThemeTokens.fromJson` and the other `core/theme` files were not changed.

## Done against the plan

- Every 1.8 name, parameter and type is implemented as written. Colours come from `context.tokens` or `context.ext`. The only raw colours are the subtle values in `token_ext.dart`.
- AppButton: height from size, or from DensityScope. Loading shows a spinner and blocks taps. Focus ring uses `border.focus`, drawn through the button shape.
- AppTextField and AppSelect: label above. Error text below, with an icon and the word; the border also turns to danger.
- AppDataTable: search, filter slot, header row, row hover, select-all and row checkboxes, bulk bar ("N selected" plus actions). Loading shows `DelayedSkeleton(SkeletonList)`, error shows `ErrorState`, empty shows `empty ?? EmptyState(title: 'Nothing here yet')`. Below 720 px the table scrolls sideways.
- PinPad: 3 by 4 grid (1-9, empty, 0, backspace), 52 px keys, dots for entered digits (with a semantics label), `onCompleted` at length then clear, `errorText` under the dots, hardware digits and Backspace via `Focus`.
- Translations and gallery as above.

## Stubbed or simplified

- Kit default strings are English literals, not ARB lookups: "Nothing here yet", "Couldn't load this", "Try again", "Cancel", "Confirm", "Clear", "Search", "Select all rows", "Select row". Reading `AppLocalizations` inside the kit would require the localisation delegates in every test. The matching ARB keys exist (`nothingHereYet`, `couldNotLoad`, `tryAgain`, `search`) for callers to use.
- `ta` and `hi` have English text only.
- Info tone has no subtle token in the Components board, so it uses the solid accent with on-accent text.
- `ConfirmDialog` is a function (`showConfirmDialog`), not a class.

## Requests for other workstreams

- WS-D (`main.dart`): add `localizationsDelegates: AppLocalizations.delegate` (plus the Flutter global delegates) and `supportedLocales` from `package:flutter_gen/gen_l10n/app_localizations.dart`. The import only resolves after `flutter gen-l10n` or `flutter pub get` with `generate: true`.
- WS-D (router): mount `ComponentGalleryScreen` at `/dev/components` when `kDebugMode`. Import `package:pos_billing/core/ui/ui.dart`, which now also exports `context.tokens`.
- Theme owner (optional): `theme_providers.dart` keeps the bootstrap tokens private. The test harness therefore duplicates them. A public accessor would remove the duplicate.

## Open risks

1. Nothing has been compiled. Expect a few analyzer nits on first build, most likely deprecation infos.
2. `flutter_localizations` pins `intl` to an exact version chosen by the SDK. The pubspec keeps `intl: ^0.19.0`. If `flutter pub get` reports a conflict, align `intl` with the SDK's pin.
3. The kit uses `WidgetState` and `WidgetStatePropertyAll`, which need Flutter 3.19 or later. `DropdownButtonFormField.value` is deprecated in newer Flutter in favour of `initialValue`. It still compiles.
4. `AppSelect` asserts if `value` is not among `items` (standard Flutter behaviour).
5. PinPad hardware-keyboard handling is untested. Icon buttons have Material's default focus highlight, not the token ring.
6. The skeleton pulse ignores reduced-motion settings.

## Memory

Nothing from the memory store was used or needed for this task.
