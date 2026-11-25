import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/ui.dart';
import 'auth_scaffold.dart';

/// Sets a new password from the link in the reset email (`?token=`).
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, this.token});

  final String? token;

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _passwordError;
  String? _confirmError;
  String? _serverError;
  bool _showPassword = false;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// Min 8 characters, at least one letter and one digit (PLAN 1.5).
  static String? validatePassword(String value) {
    if (value.length < 8) return 'Use at least 8 characters.';
    if (!RegExp(r'[A-Za-z]').hasMatch(value) || !RegExp(r'\d').hasMatch(value)) {
      return 'Use a letter and a number.';
    }
    return null;
  }

  Future<void> _submit() async {
    final password = _password.text;
    final confirm = _confirm.text;
    final rule = validatePassword(password);
    setState(() {
      _passwordError = rule;
      _confirmError = rule == null && password != confirm ? "Passwords don't match." : null;
      _serverError = null;
    });
    if (rule != null || _confirmError != null) return;

    final token = widget.token;
    if (token == null || token.isEmpty) return;

    setState(() => _busy = true);
    final ok = await ref.read(sessionProvider.notifier).resetPassword(token, password);
    if (!mounted) return;
    if (ok) {
      showAppToast(context, 'Password updated. Sign in with your new password.');
      context.go('/login');
      return;
    }
    final state = ref.read(sessionProvider);
    setState(() {
      _busy = false;
      _serverError = state.errorCode == 'RESET_TOKEN_INVALID'
          ? 'This link has expired or was already used. Request a new one.'
          : (state.error ?? "Couldn't reset your password. Try again.");
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hasToken = widget.token != null && widget.token!.isNotEmpty;

    if (!hasToken) {
      return AuthScaffold(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InlineAlert(
              message: 'This link has expired or was already used. Request a new one.',
              tone: StatusTone.danger,
            ),
            SizedBox(height: t.spacing.md),
            AppButton(
              label: 'Request a new link',
              variant: AppButtonVariant.primary,
              onPressed: () => context.go('/forgot-password'),
            ),
          ],
        ),
      );
    }

    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Choose a new password',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SizedBox(height: t.spacing.md),
          if (_serverError != null) ...[
            InlineAlert(message: _serverError!, tone: StatusTone.danger),
            SizedBox(height: t.spacing.md),
          ],
          AppTextField(
            label: 'New password',
            controller: _password,
            obscure: !_showPassword,
            autofocus: true,
            helperText: 'At least 8 characters, with a letter and a number.',
            errorText: _passwordError,
            suffix: IconButton(
              tooltip: _showPassword ? 'Hide password' : 'Show password',
              icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
          SizedBox(height: t.spacing.md),
          AppTextField(
            label: 'Confirm new password',
            controller: _confirm,
            obscure: !_showPassword,
            errorText: _confirmError,
            onSubmitted: (_) => _submit(),
          ),
          SizedBox(height: t.spacing.lg),
          AppButton(
            label: 'Reset password',
            variant: AppButtonVariant.primary,
            loading: _busy,
            onPressed: _busy ? null : _submit,
          ),
        ],
      ),
    );
  }
}
