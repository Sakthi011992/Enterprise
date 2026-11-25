import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/ui.dart';
import 'auth_scaffold.dart';

/// Password sign-in. Navigation after success is done by the router redirect.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  String? _usernameError;
  String? _passwordError;
  bool _showPassword = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _username.text.trim();
    final password = _password.text;
    setState(() {
      _usernameError = username.isEmpty ? 'Enter your username.' : null;
      _passwordError = password.isEmpty ? 'Enter your password.' : null;
    });
    if (_usernameError != null || _passwordError != null) return;
    await ref.read(sessionProvider.notifier).loginWithPassword(username, password);
  }

  static const _knownCodes = {
    'INVALID_CREDENTIALS',
    'NO_OUTLET_ACCESS',
    'NETWORK',
    'SESSION_EXPIRED',
  };

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sessionProvider);
    final hasDeviceKey = ref.watch(sessionStoreProvider).deviceKey != null;
    final t = context.tokens;
    final code = state.errorCode;

    final wrongCredentials = code == 'INVALID_CREDENTIALS';
    final genericError = state.error != null && !_knownCodes.contains(code);

    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (code == 'SESSION_EXPIRED')
            InlineAlert(message: state.error!, tone: StatusTone.warning),
          if (code == 'NETWORK')
            AppBanner(
              message: "Couldn't reach the server. Check your connection.",
              tone: StatusTone.danger,
            ),
          if (code == 'NO_OUTLET_ACCESS')
            InlineAlert(
              message: "Your account isn't linked to any outlet. Ask your admin.",
              tone: StatusTone.danger,
            ),
          if (genericError) InlineAlert(message: state.error!, tone: StatusTone.danger),
          if (code == 'NETWORK' || code == 'SESSION_EXPIRED' || code == 'NO_OUTLET_ACCESS' || genericError)
            SizedBox(height: t.spacing.md),
          AppTextField(
            label: 'Username',
            controller: _username,
            autofocus: true,
            errorText: _usernameError,
            autofillHints: const [AutofillHints.username],
            onSubmitted: (_) => _submit(),
          ),
          SizedBox(height: t.spacing.md),
          AppTextField(
            label: 'Password',
            controller: _password,
            obscure: !_showPassword,
            errorText: _passwordError ?? (wrongCredentials ? 'Wrong username or password.' : null),
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _submit(),
            suffix: IconButton(
              tooltip: _showPassword ? 'Hide password' : 'Show password',
              icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: () => context.push('/forgot-password'),
              child: const Text('Forgot password?'),
            ),
          ),
          SizedBox(height: t.spacing.sm),
          AppButton(
            label: 'Sign in',
            variant: AppButtonVariant.primary,
            loading: state.loading,
            onPressed: state.loading ? null : _submit,
          ),
          if (hasDeviceKey) ...[
            SizedBox(height: t.spacing.md),
            AppButton(
              label: 'Use staff PIN',
              variant: AppButtonVariant.ghost,
              icon: Icons.dialpad,
              onPressed: () => context.go('/pin'),
            ),
          ],
        ],
      ),
    );
  }
}
