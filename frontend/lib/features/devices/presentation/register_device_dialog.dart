import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_billing/core/theme/app_theme.dart';
import 'package:pos_billing/core/ui/ui.dart';
import 'package:pos_billing/features/outlets/data/outlets_repository.dart';
import 'package:pos_billing/features/personas/data/admin_api.dart';

import '../data/devices_repository.dart';

/// Registers a tablet, KDS, printer and so on. Shows the device key once, then closes.
Future<void> showRegisterDeviceDialog(
  BuildContext context, {
  required List<Outlet> outlets,
  required String initialOutletId,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RegisterDeviceDialog(outlets: outlets, initialOutletId: initialOutletId),
  );
}

class _RegisterDeviceDialog extends ConsumerStatefulWidget {
  const _RegisterDeviceDialog({required this.outlets, required this.initialOutletId});

  final List<Outlet> outlets;
  final String initialOutletId;

  @override
  ConsumerState<_RegisterDeviceDialog> createState() => _RegisterDeviceDialogState();
}

class _RegisterDeviceDialogState extends ConsumerState<_RegisterDeviceDialog> {
  final _name = TextEditingController();
  late String _outletId = widget.initialOutletId;
  String _type = deviceTypes.first;
  String? _nameError;
  String? _error;
  bool _saving = false;

  /// Set once the server has issued the key. The key is only in memory from here.
  RegisteredDevice? _registered;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Give the device a name, for example "Counter tablet 1"');
      return;
    }
    setState(() {
      _nameError = null;
      _error = null;
      _saving = true;
    });
    try {
      final result = await ref.read(devicesRepositoryProvider).register(
            outletId: _outletId,
            name: name,
            type: _type,
          );
      ref.invalidate(devicesListProvider(_outletId));
      if (mounted) {
        setState(() {
          _registered = result;
          _saving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = AdminApiError.from(e).friendly;
        });
      }
    }
  }

  Future<void> _copyKey() async {
    final key = _registered?.deviceKey;
    if (key == null) return;
    await Clipboard.setData(ClipboardData(text: key));
    if (mounted) showAppToast(context, 'Device key copied');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final gap = SizedBox(height: t.spacing.md);
    final registered = _registered;
    return AlertDialog(
      title: Text(registered == null ? 'Register device' : 'Device registered'),
      content: SizedBox(
        width: 420,
        child: registered == null ? _form(gap) : _keyView(registered, gap),
      ),
      actions: registered == null
          ? [
              AppButton(
                label: 'Cancel',
                variant: AppButtonVariant.ghost,
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
              ),
              AppButton(
                label: _saving ? 'Registering…' : 'Register',
                variant: AppButtonVariant.primary,
                loading: _saving,
                onPressed: _saving ? null : _register,
              ),
            ]
          : [
              AppButton(
                label: 'Done',
                variant: AppButtonVariant.primary,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
    );
  }

  Widget _form(Widget gap) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          InlineAlert(message: _error!),
          gap,
        ],
        AppSelect<String>(
          label: 'Outlet',
          value: _outletId,
          items: [for (final o in widget.outlets) AppSelectItem(o.id, o.name)],
          onChanged: (v) {
            if (v != null) setState(() => _outletId = v);
          },
        ),
        gap,
        AppTextField(
          label: 'Device name',
          controller: _name,
          errorText: _nameError,
          autofocus: true,
          onSubmitted: (_) => _register(),
        ),
        gap,
        AppSelect<String>(
          label: 'Device type',
          value: _type,
          items: [for (final type in deviceTypes) AppSelectItem(type, deviceTypeLabel(type))],
          onChanged: (v) {
            if (v != null) setState(() => _type = v);
          },
        ),
      ],
    );
  }

  Widget _keyView(RegisteredDevice result, Widget gap) {
    final t = context.tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${result.device.name} is registered. Copy its key now.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        gap,
        InlineAlert(
          message: "This key is shown once. Enter it on the tablet's PIN screen.",
          tone: StatusTone.warning,
        ),
        gap,
        Container(
          padding: EdgeInsets.all(t.spacing.md),
          decoration: BoxDecoration(
            color: t.color.background.surface,
            borderRadius: BorderRadius.circular(t.radius.md),
            border: Border.all(color: t.color.border.standard, width: t.borderWidth.hairline),
          ),
          child: SelectableText(
            result.deviceKey,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        gap,
        AppButton(label: 'Copy key', icon: Icons.copy_outlined, onPressed: _copyKey),
      ],
    );
  }
}
