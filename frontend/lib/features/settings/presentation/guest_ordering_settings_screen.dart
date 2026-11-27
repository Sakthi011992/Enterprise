import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/auth/permission_keys.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/ui/ui.dart';
import '../../guest_requests/data/guest_models.dart';
import '../../guest_requests/data/guest_requests_providers.dart';
import '../../guest_requests/data/guest_requests_repository.dart';

/// `/settings/guest-ordering`: Settings › Feature configuration › Guest
/// ordering (PLAN 2.1). One app-wide configuration for routing, verification,
/// rules and checkout.
class GuestOrderingSettingsScreen extends ConsumerWidget {
  const GuestOrderingSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final canView = can(ref, Perm.adminSettings, AccessLevel.view);
    final canEdit = can(ref, Perm.adminSettings, AccessLevel.edit);
    final config = ref.watch(guestConfigProvider);
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(t.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageHeader(title: 'Guest ordering', breadcrumb: 'Settings › Feature configuration'),
            SizedBox(height: t.spacing.sm),
            Expanded(
              child: !canView
                  ? const EmptyState(title: "You can't see feature configuration.")
                  : config.when(
                      loading: () => const DelayedSkeleton(child: SkeletonList()),
                      error: (e, _) => ErrorState(
                        message: ApiError.from(e).message,
                        onRetry: () => ref.invalidate(guestConfigProvider),
                      ),
                      data: (c) => GuestOrderingForm(initial: c, canEdit: canEdit),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class GuestOrderingForm extends ConsumerStatefulWidget {
  const GuestOrderingForm({super.key, required this.initial, this.canEdit = true});

  final GuestConfig initial;
  final bool canEdit;

  @override
  ConsumerState<GuestOrderingForm> createState() => _GuestOrderingFormState();
}

class _GuestOrderingFormState extends ConsumerState<GuestOrderingForm> {
  late GuestConfig _c = widget.initial;
  late GuestConfig _saved = widget.initial;
  String? _newOtp;
  late final _minAge = TextEditingController(text: '${widget.initial.minAge}');
  late final _ttl = TextEditingController(text: '${widget.initial.requestTtlMinutes}');
  String? _minAgeError;
  String? _ttlError;
  String? _formError;
  bool _saving = false;

  @override
  void dispose() {
    _minAge.dispose();
    _ttl.dispose();
    super.dispose();
  }

  void _set(GuestConfig c) => setState(() {
        _c = c;
        _formError = null;
      });

  void _cancel() => setState(() {
        _c = _saved;
        _newOtp = null;
        _minAge.text = '${_saved.minAge}';
        _ttl.text = '${_saved.requestTtlMinutes}';
        _minAgeError = _ttlError = _formError = null;
      });

  bool _validate() {
    final age = int.tryParse(_minAge.text.trim());
    final ttl = int.tryParse(_ttl.text.trim());
    setState(() {
      _minAgeError = _c.ageGate && (age == null || age < 18 || age > 99)
          ? 'Enter an age from 18 to 99'
          : null;
      _ttlError = ttl == null || ttl < 1 || ttl > 120 ? 'Enter 1 to 120 minutes' : null;
      _formError = _c.method == GuestVerifyMethods.staticOtp && !_c.hasStaticOtp && _newOtp == null
          ? 'Set a static OTP code before saving.'
          : null;
    });
    return _minAgeError == null && _ttlError == null && _formError == null;
  }

  Future<void> _save() async {
    if (!_validate()) return;
    final next = _c.copyWith(
      minAge: int.tryParse(_minAge.text.trim()) ?? _c.minAge,
      requestTtlMinutes: int.parse(_ttl.text.trim()),
    );
    setState(() => _saving = true);
    try {
      final saved = await ref.read(guestRequestsRepositoryProvider).saveConfig(next, newStaticOtp: _newOtp);
      if (!mounted) return;
      setState(() {
        _saved = _c = saved.copyWith(hasStaticOtp: saved.hasStaticOtp || _newOtp != null);
        _newOtp = null;
      });
      showAppToast(context, 'Guest ordering saved. New rounds use these settings.');
    } catch (e) {
      if (mounted) setState(() => _formError = ApiError.from(e).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setNewCode() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => SetOtpDialog(length: _c.codeLength),
    );
    if (code == null) return;
    setState(() {
      _newOtp = code;
      _formError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final edit = widget.canEdit && !_saving;

    final cards = <Widget>[
      _Section(
        title: 'How orders reach the kitchen',
        subtitle: 'Applies to new rounds as soon as you save.',
        child: Row(
          children: [
            Expanded(
              child: _OptionTile(
                key: const ValueKey('routing-direct'),
                title: 'Direct to kitchen',
                subtitle: 'Guest orders go straight to KOT/BOT.',
                selected: _c.routing == GuestRouting.direct,
                onTap: edit ? () => _set(_c.copyWith(routing: GuestRouting.direct)) : null,
              ),
            ),
            SizedBox(width: t.spacing.sm),
            Expanded(
              child: _OptionTile(
                key: const ValueKey('routing-waiter'),
                title: 'Via waiter',
                subtitle: 'A waiter checks and confirms each round first.',
                selected: _c.routing == GuestRouting.waiter,
                onTap: edit ? () => _set(_c.copyWith(routing: GuestRouting.waiter)) : null,
              ),
            ),
          ],
        ),
      ),
      _Section(
        title: 'How guests verify',
        subtitle: 'Guests enter their name and mobile number, then this code.',
        child: Column(
          children: [
            _RadioRow(
              key: const ValueKey('verify-static'),
              title: 'Static OTP',
              subtitleWidget: Text.rich(TextSpan(children: [
                TextSpan(text: _newOtp != null ? 'New code (saved when you save) ' : 'Current code '),
                TextSpan(
                  text: _newOtp != null || _c.hasStaticOtp ? '•' * _c.codeLength : 'not set',
                  style: TextStyle(fontFamily: t.typography.monoFamily),
                ),
              ])),
              selected: _c.method == GuestVerifyMethods.staticOtp,
              onTap: edit ? () => _set(_c.copyWith(method: GuestVerifyMethods.staticOtp)) : null,
              trailing: AppButton(
                label: 'Set new code',
                size: AppControlSize.sm,
                onPressed: edit ? _setNewCode : null,
              ),
            ),
            _RadioRow(
              key: const ValueKey('verify-pin'),
              title: 'Table PIN',
              subtitle: 'New 4-digit PIN each time staff seat a table',
              selected: _c.method == GuestVerifyMethods.tablePin,
              onTap: edit ? () => _set(_c.copyWith(method: GuestVerifyMethods.tablePin)) : null,
            ),
            const _RadioRow(
              key: ValueKey('verify-sms'),
              title: 'SMS OTP',
              selected: false,
              onTap: null,
              trailing: _ComingSoon(),
            ),
          ],
        ),
      ),
      _Section(
        title: 'Rules',
        child: Column(
          children: [
            _ToggleRow(
              title: 'Only seated tables can order',
              subtitle: 'Before seating, the menu is view-only',
              value: _c.requireSeated,
              onChanged: edit ? (v) => _set(_c.copyWith(requireSeated: v)) : null,
            ),
            _ToggleRow(
              title: 'Age check for alcohol',
              subtitle: 'Minimum age ${_minAge.text}',
              value: _c.ageGate,
              onChanged: edit ? (v) => _set(_c.copyWith(ageGate: v)) : null,
            ),
            if (_c.ageGate)
              Padding(
                padding: EdgeInsets.only(bottom: t.spacing.sm),
                child: AppTextField(
                  key: const ValueKey('min-age'),
                  label: 'Minimum age',
                  controller: _minAge,
                  errorText: _minAgeError,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() => _minAgeError = null),
                ),
              ),
            _ToggleRow(
              title: 'Guests can cancel a waiting round',
              subtitle: 'Until a waiter confirms it',
              value: _c.allowGuestCancel,
              onChanged: edit ? (v) => _set(_c.copyWith(allowGuestCancel: v)) : null,
            ),
            AppTextField(
              key: const ValueKey('ttl'),
              label: 'Expire unconfirmed rounds after (min)',
              helperText: 'Guest is told it expired',
              controller: _ttl,
              errorText: _ttlError,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() => _ttlError = null),
            ),
          ],
        ),
      ),
      const _Section(
        title: 'Checkout',
        subtitle: 'How guests settle the bill.',
        child: Column(
          children: [
            _RadioRow(title: 'Ask for the bill (waiter brings it)', selected: true, onTap: null),
            _RadioRow(key: ValueKey('pay-online'), title: 'Pay online', selected: false, onTap: null, trailing: _ComingSoon()),
          ],
        ),
      ),
    ];

    return ListView(
      children: [
        _Section(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Let guests order from the table QR', style: text.titleMedium),
                    Text('Applies to every outlet and table.', style: text.bodySmall),
                  ],
                ),
              ),
              Switch(
                key: const ValueKey('guest-enabled'),
                value: _c.enabled,
                onChanged: edit ? (v) => _set(_c.copyWith(enabled: v)) : null,
              ),
            ],
          ),
        ),
        SizedBox(height: t.spacing.md),
        LayoutBuilder(builder: (context, c) {
          if (c.maxWidth < 760) {
            return Column(children: [
              for (final card in cards) ...[card, SizedBox(height: t.spacing.md)],
            ]);
          }
          final half = (c.maxWidth - t.spacing.md) / 2;
          return Wrap(
            spacing: t.spacing.md,
            runSpacing: t.spacing.md,
            children: [for (final card in cards) SizedBox(width: half, child: card)],
          );
        }),
        if (_formError != null) ...[
          SizedBox(height: t.spacing.md),
          InlineAlert(message: _formError!),
        ],
        SizedBox(height: t.spacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(label: 'Cancel', onPressed: edit ? _cancel : null),
            SizedBox(width: t.spacing.sm),
            AppButton(
              label: 'Save changes',
              variant: AppButtonVariant.primary,
              loading: _saving,
              onPressed: widget.canEdit && !_saving ? _save : null,
            ),
          ],
        ),
        SizedBox(height: t.spacing.md),
      ],
    );
  }
}

/// "Set new code": digits only, exactly [length] long, typed twice.
class SetOtpDialog extends StatefulWidget {
  const SetOtpDialog({super.key, required this.length});

  final int length;

  @override
  State<SetOtpDialog> createState() => _SetOtpDialogState();
}

class _SetOtpDialogState extends State<SetOtpDialog> {
  final _code = TextEditingController();
  final _again = TextEditingController();
  String? _codeError;
  String? _againError;

  @override
  void dispose() {
    _code.dispose();
    _again.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _code.text.trim();
    setState(() {
      _codeError = RegExp('^\\d{${widget.length}}\$').hasMatch(code)
          ? null
          : 'Enter ${widget.length} digits';
      _againError = _codeError == null && _again.text.trim() != code ? "The codes don't match" : null;
    });
    if (_codeError == null && _againError == null) Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AlertDialog(
      backgroundColor: t.color.background.raised,
      surfaceTintColor: Colors.transparent,
      title: const Text('Set new code'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Guests type this ${widget.length}-digit code after their name and mobile number. '
                'Staff tell guests the code.', style: Theme.of(context).textTheme.bodySmall),
            SizedBox(height: t.spacing.sm),
            AppTextField(
              key: const ValueKey('otp-new'),
              label: 'New code',
              controller: _code,
              errorText: _codeError,
              obscure: true,
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: t.spacing.sm),
            AppTextField(
              key: const ValueKey('otp-again'),
              label: 'Type it again',
              controller: _again,
              errorText: _againError,
              obscure: true,
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        AppButton(label: 'Cancel', variant: AppButtonVariant.ghost, onPressed: () => Navigator.of(context).pop()),
        AppButton(label: 'Set code', variant: AppButtonVariant.primary, onPressed: _submit),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.child, this.title, this.subtitle});

  final String? title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: EdgeInsets.all(t.spacing.md),
      decoration: BoxDecoration(
        color: t.color.background.raised,
        borderRadius: BorderRadius.circular(t.radius.lg),
        border: Border.all(color: t.color.border.subtle, width: t.borderWidth.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) Text(title!, style: text.titleMedium),
          if (subtitle != null)
            Text(subtitle!, style: text.bodySmall?.copyWith(color: t.color.content.secondary)),
          if (title != null || subtitle != null) SizedBox(height: t.spacing.sm),
          child,
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ext = context.ext;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(t.radius.md),
        child: Container(
          padding: EdgeInsets.all(t.spacing.sm + 4),
          decoration: BoxDecoration(
            color: selected ? ext.accentSubtle : t.color.background.surface,
            borderRadius: BorderRadius.circular(t.radius.md),
            border: Border.all(
              color: selected ? t.color.border.accent : t.color.border.subtle,
              width: selected ? t.borderWidth.thick : t.borderWidth.hairline,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: text.titleSmall?.copyWith(
                      color: selected ? ext.onAccentSubtle : t.color.content.primary)),
              Text(subtitle, style: text.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadioRow extends StatelessWidget {
  const _RadioRow({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.subtitleWidget,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final disabled = onTap == null && !selected;
    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(t.radius.md),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: t.spacing.xs),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 20,
                color: selected ? t.color.background.accent : t.color.content.muted,
              ),
              SizedBox(width: t.spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    if (subtitleWidget != null)
                      DefaultTextStyle.merge(
                          style: text.bodySmall?.copyWith(color: t.color.content.secondary),
                          child: subtitleWidget!)
                    else if (subtitle != null)
                      Text(subtitle!, style: text.bodySmall?.copyWith(color: t.color.content.secondary)),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({required this.title, required this.subtitle, required this.value, required this.onChanged});

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              Text(subtitle, style: text.bodySmall),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon();

  @override
  Widget build(BuildContext context) => const StatusBadge(label: 'Coming soon', tone: StatusTone.neutral);
}
