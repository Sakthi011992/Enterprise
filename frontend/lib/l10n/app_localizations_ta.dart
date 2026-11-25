// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Tamil (`ta`).
class AppLocalizationsTa extends AppLocalizations {
  AppLocalizationsTa([String locale = 'ta']) : super(locale);

  @override
  String get appTitle => 'POS Billing';

  @override
  String get signIn => 'Sign in';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get invalidCredentials => 'Wrong username or password.';

  @override
  String get accountLocked =>
      'Too many attempts. Ask your admin to unlock this account.';

  @override
  String get resetPassword => 'Reset password';

  @override
  String get newPassword => 'New password';

  @override
  String get sendResetLink => 'Send reset link';

  @override
  String get resetLinkSent =>
      'If that account exists, we have sent a reset link.';

  @override
  String get chooseOutlet => 'Choose an outlet';

  @override
  String get enterPin => 'Enter your PIN';

  @override
  String pinWrongAttemptsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Wrong PIN. $count attempts left.',
      one: 'Wrong PIN. 1 attempt left.',
    );
    return '$_temp0';
  }

  @override
  String pinLocked(int minutes) {
    return 'Too many wrong PINs. Try again in $minutes min.';
  }

  @override
  String get search => 'Search';

  @override
  String get notifications => 'Notifications';

  @override
  String get markAllRead => 'Mark all read';

  @override
  String get signOut => 'Sign out';

  @override
  String get switchOutlet => 'Switch outlet';

  @override
  String get language => 'Language';

  @override
  String get darkMode => 'Dark mode';

  @override
  String get pinned => 'Pinned';

  @override
  String get nothingHereYet => 'Nothing here yet';

  @override
  String get couldNotLoad => 'Couldn’t load this. Try again.';

  @override
  String get tryAgain => 'Try again';

  @override
  String get saving => 'Saving…';

  @override
  String get saved => 'Saved';

  @override
  String get undo => 'Undo';
}
