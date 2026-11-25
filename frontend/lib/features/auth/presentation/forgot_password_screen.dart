import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/ui.dart';
import 'auth_scaffold.dart';

/// Asks for a username or email. The success message is the same whether or
/// not the account exists.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _controller = TextEditingController();
  String? _fieldError;
  String? _serverError;
  bool _busy = false;
  bool _sent = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _fieldError = 'Enter your username or email.');
      return;
    }
    setState(() {
      _fieldError = null;
      _serverError = null;
      _busy = true;
    });
    final ok = await ref.read(sessionProvider.notifier).forgotPassword(value);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) {
        _sent = true;
      } else {
        _serverError = ref.read(sessionProvider).error ?? "Couldn't send the link. Try again.";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Reset your password',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SizedBox(height: t.spacing.md),
          if (_sent)
            InlineAlert(
              message: "If that account exists, we've sent a reset link.",
              tone: StatusTone.success,
            )
          else ...[
            if (_serverError != null)
              InlineAlert(message: _serverError!, tone: StatusTone.danger),
            AppTextField(
              label: 'Username or email',
              controller: _controller,
              autofocus: true,
              errorText: _fieldError,
              onSubmitted: (_) => _submit(),
            ),
            SizedBox(height: t.spacing.lg),
            AppButton(
              label: 'Send reset link',
              variant: AppButtonVariant.primary,
              loading: _busy,
              onPressed: _busy ? null : _submit,
            ),
          ],
          SizedBox(height: t.spacing.md),
          AppButton(
            label: 'Back to sign in',
            variant: AppButtonVariant.ghost,
            onPressed: () => context.go('/login'),
          ),
        ],
      ),
    );
  }
}
