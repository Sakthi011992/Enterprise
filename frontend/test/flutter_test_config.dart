import 'dart:async';

import 'package:pos_billing/core/theme/app_theme.dart';

/// Runs before every test file: keeps tests off the network by not fetching Google Fonts.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AppFonts.enabled = false;
  await testMain();
}
