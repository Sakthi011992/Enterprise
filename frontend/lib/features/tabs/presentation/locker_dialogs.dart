import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/ui/ui.dart';
import '../../pos/presentation/dialogs/dialog_frame.dart';
import '../data/tabs_models.dart';
import '../data/tabs_repository.dart';
import '../domain/tab_rules.dart';

/// Stores a bottle in the bar locker. Resolves to the new [LockerView].
Future<LockerView?> showStoreBottleDialog(BuildContext context) {
  return showDialog<LockerView>(
    context: context,
    builder: (_) => const _StoreBottleDialog(),
  );
}

/// Takes ml out of a stored bottle. Resolves to the updated [LockerView].
Future<LockerView?> showServeBottleDialog(BuildContext context, LockerView locker) {
  return showDialog<LockerView>(
    context: context,
    builder: (_) => _ServeBottleDialog(locker: locker),
  );
}

/// Edits guest details, the amount left (an ADJUST event), expiry and note.
Future<LockerView?> showEditLockerDialog(BuildContext context, LockerView locker) {
  return showDialog<LockerView>(
    context: context,
    builder: (_) => _EditLockerDialog(locker: locker),
  );
}

/// Removes a bottle from the locker. The reason is required by the server.
Future<LockerView?> showRemoveLockerDialog(BuildContext context, LockerView locker) {
  return showDialog<LockerView>(
    context: context,
    builder: (_) => _RemoveLockerDialog(locker: locker),
  );
}

/// Pick a date in the dialog. Shows the chosen date and a Change button.
class _ExpiryField extends StatelessWidget {
  const _ExpiryField({required this.date, required this.onChanged, this.enabled = true});

  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Expanded(
          child: Text(
            'Expires ${shortDate(date)} ${date.year}',
            style: TextStyle(color: t.color.content.primary),
          ),
        ),
        TextButton(
          onPressed: !enabled
              ? null
              : () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2040),
                  );
                  if (picked != null) onChanged(picked);
                },
          child: const Text('Change'),
        ),
      ],
    );
  }
}

class _StoreBottleDialog extends ConsumerStatefulWidget {
  const _StoreBottleDialog();

  @override
  ConsumerState<_StoreBottleDialog> createState() => _StoreBottleDialogState();
}

class _StoreBottleDialogState extends ConsumerState<_StoreBottleDialog> {
  final _guest = TextEditingController();
  final _mobile = TextEditingController();
  final _card = TextEditingController();
  final _bottle = TextEditingController();
  final _ml = TextEditingController(text: '750');
  final _remaining = TextEditingController(text: '750');
  final _note = TextEditingController();
  DateTime _expires = DateTime.now().add(const Duration(days: 90));
  Map<String, String> _errors = const {};
  String? _serverError;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_guest, _mobile, _card, _bottle, _ml, _remaining, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _setMl(String value) {
    setState(() {
      _ml.text = value;
      _remaining.text = value;
    });
  }

  Future<void> _save() async {
    final ml = int.tryParse(_ml.text.trim()) ?? 0;
    final remaining = int.tryParse(_remaining.text.trim()) ?? 0;
    final errors = <String, String>{};
    if (_guest.text.trim().isEmpty) errors['guest'] = 'Enter the guest name.';
    if (_bottle.text.trim().isEmpty) errors['bottle'] = 'Enter the bottle name.';
    if (ml <= 0) errors['ml'] = 'Enter a bottle size above 0 ml.';
    if (remaining <= 0 || remaining > ml) {
      errors['remaining'] = 'Enter between 1 and $ml ml.';
    }
    setState(() {
      _errors = errors;
      _serverError = null;
    });
    if (errors.isNotEmpty) return;

    setState(() => _busy = true);
    try {
      final mobile = _mobile.text.trim();
      final card = _card.text.trim();
      final note = _note.text.trim();
      final locker = await ref.read(tabsRepositoryProvider).storeBottle(
            LockerCreateRequest(
              guestName: _guest.text.trim(),
              mobile: mobile.isEmpty ? null : mobile,
              cardLast4: card.isEmpty ? null : card,
              bottleName: _bottle.text.trim(),
              bottleMl: ml,
              remainingMl: remaining,
              expiresAt: isoDate(_expires),
              note: note.isEmpty ? null : note,
            ),
          );
      if (!mounted) return;
      Navigator.of(context).pop(locker);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _serverError = tabErrorMessage(ApiError.from(e));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return PosDialogFrame(
      title: 'Store a bottle',
      subtitle: 'The guest collects it later from the bar locker.',
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Store bottle',
          variant: AppButtonVariant.primary,
          loading: _busy,
          onPressed: _busy ? null : _save,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_serverError != null) ...[
            InlineAlert(message: _serverError!),
            SizedBox(height: t.spacing.sm),
          ],
          AppTextField(label: 'Guest name', controller: _guest, errorText: _errors['guest']),
          SizedBox(height: t.spacing.sm),
          AppTextField(label: 'Mobile', controller: _mobile, keyboardType: TextInputType.phone),
          SizedBox(height: t.spacing.sm),
          AppTextField(
            label: 'Card last 4 digits (optional)',
            controller: _card,
            keyboardType: TextInputType.number,
          ),
          SizedBox(height: t.spacing.sm),
          AppTextField(label: 'Bottle', controller: _bottle, errorText: _errors['bottle']),
          SizedBox(height: t.spacing.sm),
          Text('Bottle size', style: Theme.of(context).textTheme.labelLarge),
          SizedBox(height: t.spacing.xs),
          Wrap(
            spacing: t.spacing.sm,
            runSpacing: t.spacing.sm,
            children: [
              for (final size in const ['375', '650', '750', '1000'])
                PosChoiceChip(
                  label: '$size ml',
                  selected: _ml.text == size,
                  onTap: _busy ? null : () => _setMl(size),
                ),
            ],
          ),
          SizedBox(height: t.spacing.sm),
          AppTextField(
            label: 'Left in the bottle (ml)',
            controller: _remaining,
            keyboardType: TextInputType.number,
            errorText: _errors['remaining'] ?? _errors['ml'],
          ),
          SizedBox(height: t.spacing.sm),
          _ExpiryField(
            date: _expires,
            enabled: !_busy,
            onChanged: (d) => setState(() => _expires = d),
          ),
          SizedBox(height: t.spacing.sm),
          AppTextField(label: 'Note (optional)', controller: _note),
        ],
      ),
    );
  }
}

class _ServeBottleDialog extends ConsumerStatefulWidget {
  const _ServeBottleDialog({required this.locker});

  final LockerView locker;

  @override
  ConsumerState<_ServeBottleDialog> createState() => _ServeBottleDialogState();
}

class _ServeBottleDialogState extends ConsumerState<_ServeBottleDialog> {
  final _custom = TextEditingController();
  int? _chosen;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  int get _ml => _chosen ?? int.tryParse(_custom.text.trim()) ?? 0;

  Future<void> _serve() async {
    final ml = _ml;
    if (ml <= 0) {
      setState(() => _error = 'Pick an amount above 0 ml.');
      return;
    }
    if (ml > widget.locker.remainingMl) {
      setState(() => _error = 'Only ${widget.locker.remainingMl} ml is left in this bottle.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await ref
          .read(tabsRepositoryProvider)
          .serveBottle(widget.locker.id, ml: ml);
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = tabErrorMessage(ApiError.from(e));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final locker = widget.locker;
    final ml = _ml;
    final serveLabel = ml > 0 ? 'Serve $ml ml' : 'Serve';
    return PosDialogFrame(
      title: 'Serve from ${locker.guestLabel}',
      subtitle: '${locker.bottleName} · ${locker.remainingMl} ml left',
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: serveLabel,
          variant: AppButtonVariant.primary,
          loading: _busy,
          onPressed: _busy ? null : _serve,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            InlineAlert(message: _error!),
            SizedBox(height: t.spacing.sm),
          ],
          Wrap(
            spacing: t.spacing.sm,
            runSpacing: t.spacing.sm,
            children: [
              for (final ml in const [30, 60, 90])
                PosChoiceChip(
                  label: '$ml ml',
                  selected: _chosen == ml,
                  minHeight: 52,
                  onTap: _busy
                      ? null
                      : () => setState(() {
                            _chosen = ml;
                            _custom.clear();
                          }),
                ),
            ],
          ),
          SizedBox(height: t.spacing.sm),
          AppTextField(
            label: 'Custom ml',
            controller: _custom,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() => _chosen = null),
          ),
        ],
      ),
    );
  }
}

class _EditLockerDialog extends ConsumerStatefulWidget {
  const _EditLockerDialog({required this.locker});

  final LockerView locker;

  @override
  ConsumerState<_EditLockerDialog> createState() => _EditLockerDialogState();
}

class _EditLockerDialogState extends ConsumerState<_EditLockerDialog> {
  late final _guest = TextEditingController(text: widget.locker.guestName);
  late final _mobile = TextEditingController(text: widget.locker.mobile ?? '');
  late final _remaining = TextEditingController(text: '${widget.locker.remainingMl}');
  final _note = TextEditingController();
  late DateTime _expires = widget.locker.expiresAt ?? DateTime.now();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_guest, _mobile, _remaining, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final remaining = int.tryParse(_remaining.text.trim());
    if (_guest.text.trim().isEmpty) {
      setState(() => _error = 'Enter the guest name.');
      return;
    }
    if (remaining == null || remaining < 0 || remaining > widget.locker.bottleMl) {
      setState(() => _error = 'Enter between 0 and ${widget.locker.bottleMl} ml.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final mobile = _mobile.text.trim();
      final note = _note.text.trim();
      final updated = await ref.read(tabsRepositoryProvider).updateLocker(
            widget.locker.id,
            LockerEditRequest(
              guestName: _guest.text.trim(),
              mobile: mobile.isEmpty ? null : mobile,
              remainingMl: remaining == widget.locker.remainingMl ? null : remaining,
              expiresAt: isoDate(_expires),
              note: note.isEmpty ? null : note,
            ),
          );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = tabErrorMessage(ApiError.from(e));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return PosDialogFrame(
      title: 'Edit bottle',
      subtitle: widget.locker.bottleName,
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Save',
          variant: AppButtonVariant.primary,
          loading: _busy,
          onPressed: _busy ? null : _save,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            InlineAlert(message: _error!),
            SizedBox(height: t.spacing.sm),
          ],
          AppTextField(label: 'Guest name', controller: _guest),
          SizedBox(height: t.spacing.sm),
          AppTextField(label: 'Mobile', controller: _mobile, keyboardType: TextInputType.phone),
          SizedBox(height: t.spacing.sm),
          AppTextField(
            label: 'Left in the bottle (ml)',
            controller: _remaining,
            keyboardType: TextInputType.number,
            helperText: 'Changing this records an adjustment in the bottle history.',
          ),
          SizedBox(height: t.spacing.sm),
          _ExpiryField(
            date: _expires,
            enabled: !_busy,
            onChanged: (d) => setState(() => _expires = d),
          ),
          SizedBox(height: t.spacing.sm),
          AppTextField(label: 'Note (optional)', controller: _note),
        ],
      ),
    );
  }
}

class _RemoveLockerDialog extends ConsumerStatefulWidget {
  const _RemoveLockerDialog({required this.locker});

  final LockerView locker;

  @override
  ConsumerState<_RemoveLockerDialog> createState() => _RemoveLockerDialogState();
}

class _RemoveLockerDialogState extends ConsumerState<_RemoveLockerDialog> {
  final _reason = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _remove() async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Say why the bottle is being removed.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await ref
          .read(tabsRepositoryProvider)
          .removeLocker(widget.locker.id, reason: reason);
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = tabErrorMessage(ApiError.from(e));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return PosDialogFrame(
      title: 'Remove ${widget.locker.bottleName}?',
      subtitle: '${widget.locker.guestLabel} · ${widget.locker.remainingMl} ml left',
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Remove bottle',
          variant: AppButtonVariant.danger,
          loading: _busy,
          onPressed: _busy ? null : _remove,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            InlineAlert(message: _error!),
            SizedBox(height: t.spacing.sm),
          ],
          AppTextField(
            label: 'Reason',
            controller: _reason,
            hint: 'Guest collected it, or the bottle was returned',
            autofocus: true,
          ),
        ],
      ),
    );
  }
}
