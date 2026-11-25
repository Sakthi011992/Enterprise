import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/ui.dart';
import '../data/auth_repository.dart';
import 'auth_scaffold.dart';

/// Staff list for this tablet's outlet. Re-fetched when the screen opens.
final pinStaffProvider = FutureProvider.autoDispose<PinStaffList>((ref) {
  return ref.watch(authRepositoryProvider).pinStaff();
});

/// Staff PIN sign-in on a registered shared tablet.
class PinLoginScreen extends ConsumerStatefulWidget {
  const PinLoginScreen({super.key});

  @override
  ConsumerState<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends ConsumerState<PinLoginScreen> {
  final _deviceKey = TextEditingController();
  PinStaffMember? _selected;
  Timer? _ticker;
  String? _setupError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(sessionProvider.notifier).clearError();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _deviceKey.dispose();
    super.dispose();
  }

  DateTime? _lockedUntil(SessionState state) {
    if (state.errorCode != 'PIN_LOCKED') return null;
    final raw = state.errorDetails?['lockedUntil'];
    return raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
  }

  void _startTicker() {
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final until = _lockedUntil(ref.read(sessionProvider));
      final remaining = until == null ? Duration.zero : until.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        _ticker?.cancel();
        _ticker = null;
        ref.read(sessionProvider.notifier).clearError();
      }
      setState(() {});
    });
  }

  String _mmss(Duration d) {
    final total = d.inSeconds < 0 ? 0 : d.inSeconds;
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String? _pinError(SessionState state) {
    switch (state.errorCode) {
      case 'PIN_INVALID':
        final left = state.errorDetails?['attemptsLeft'];
        if (left is num) {
          final n = left.toInt();
          return n == 1 ? 'Wrong PIN. 1 attempt left.' : 'Wrong PIN. $n attempts left.';
        }
        return 'Wrong PIN.';
      case SessionErrorCode.network:
        return "Couldn't reach the server.";
      case 'PIN_LOCKED':
        return null; // shown as a banner with the countdown
      default:
        return state.error;
    }
  }

  Future<void> _saveDeviceKey() async {
    final value = _deviceKey.text.trim();
    if (value.isEmpty) {
      setState(() => _setupError = 'Paste the device key from the admin Devices screen.');
      return;
    }
    await ref.read(sessionStoreProvider).setDeviceKey(value);
    if (!mounted) return;
    setState(() => _setupError = null);
    ref.invalidate(pinStaffProvider);
  }

  Future<void> _resetDeviceKey() async {
    await ref.read(sessionStoreProvider).setDeviceKey(null);
    if (!mounted) return;
    ref.invalidate(pinStaffProvider);
    setState(() => _selected = null);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    ref.listen<SessionState>(sessionProvider, (prev, next) {
      if (next.errorCode == 'PIN_LOCKED') _startTicker();
    });
    final hasKey = ref.watch(sessionStoreProvider).deviceKey != null;

    if (!hasKey) return _buildSetup(context);

    final state = ref.watch(sessionProvider);
    final staff = ref.watch(pinStaffProvider);

    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          staff.when(
            loading: () => const DelayedSkeleton(child: SkeletonList(rows: 3)),
            error: (e, _) => _buildStaffError(context, e),
            data: (list) => _buildStaff(context, list, state),
          ),
          SizedBox(height: t.spacing.lg),
          AppButton(
            label: 'Sign in with password',
            variant: AppButtonVariant.ghost,
            onPressed: () => context.go('/login'),
          ),
        ],
      ),
    );
  }

  Widget _buildSetup(BuildContext context) {
    final t = context.tokens;
    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "This tablet isn't set up yet",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SizedBox(height: t.spacing.xs),
          Text(
            'Register this tablet under Devices in the admin app, then paste the key it shows.',
            textAlign: TextAlign.center,
            style: TextStyle(color: t.color.content.secondary),
          ),
          SizedBox(height: t.spacing.md),
          AppTextField(
            label: 'Device key',
            controller: _deviceKey,
            hint: 'Paste the key',
            helperText: 'Shown once when the device is registered.',
            errorText: _setupError,
            onSubmitted: (_) => _saveDeviceKey(),
          ),
          SizedBox(height: t.spacing.md),
          AppButton(
            label: 'Save device key',
            variant: AppButtonVariant.primary,
            onPressed: _saveDeviceKey,
          ),
          SizedBox(height: t.spacing.sm),
          AppButton(
            label: 'Sign in with password',
            variant: AppButtonVariant.ghost,
            onPressed: () => context.go('/login'),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffError(BuildContext context, Object error) {
    final t = context.tokens;
    final err = ApiError.from(error);
    if (err.code == SessionErrorCode.deviceInvalid || err.status == 401) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InlineAlert(
            message: "This tablet's key is no longer valid. Set it up again.",
            tone: StatusTone.danger,
          ),
          SizedBox(height: t.spacing.md),
          AppButton(
            label: 'Set up tablet again',
            variant: AppButtonVariant.primary,
            onPressed: _resetDeviceKey,
          ),
        ],
      );
    }
    return ErrorState(
      message: 'The staff list did not load. Try again.',
      onRetry: () => ref.invalidate(pinStaffProvider),
    );
  }

  Widget _buildStaff(BuildContext context, PinStaffList list, SessionState state) {
    final t = context.tokens;
    final selected = _selected;

    if (selected == null) {
      if (list.staff.isEmpty) {
        return EmptyState(
          title: 'No staff can sign in here',
          message: 'Give a staff member a PIN from Users in the admin app.',
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Who is working?',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SizedBox(height: t.spacing.xs),
          Text(
            list.outletName,
            textAlign: TextAlign.center,
            style: TextStyle(color: t.color.content.secondary),
          ),
          SizedBox(height: t.spacing.md),
          for (final member in list.staff) ...[
            AppCard(
              child: InkWell(
                borderRadius: BorderRadius.circular(t.radius.md),
                onTap: () => setState(() => _selected = member),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(member.displayName,
                          style: Theme.of(context).textTheme.titleSmall),
                    ),
                    StatusBadge(label: member.personaName),
                  ],
                ),
              ),
            ),
            SizedBox(height: t.spacing.sm),
          ],
        ],
      );
    }

    final until = _lockedUntil(state);
    final remaining = until == null ? Duration.zero : until.difference(DateTime.now());
    final locked = remaining > Duration.zero;
    if (locked) _startTicker();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton(
            label: 'Not you?',
            variant: AppButtonVariant.ghost,
            onPressed: () => setState(() => _selected = null),
          ),
        ),
        Text(
          'Enter PIN for ${selected.displayName}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        SizedBox(height: t.spacing.md),
        if (locked) ...[
          AppBanner(
            message: 'Locked after too many wrong PINs. Try again in ${_mmss(remaining)}.',
            tone: StatusTone.warning,
          ),
          SizedBox(height: t.spacing.md),
        ],
        PinPad(
          length: 4,
          enabled: !locked && !state.loading,
          errorText: _pinError(state),
          onCompleted: (pin) => ref
              .read(sessionProvider.notifier)
              .loginWithPin(selected.userId, pin),
        ),
      ],
    );
  }
}
