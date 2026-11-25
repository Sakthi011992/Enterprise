import 'package:flutter/material.dart';
import 'package:pos_billing/core/theme/app_theme.dart';
import 'package:pos_billing/core/ui/ui.dart';

import '../data/persona_models.dart';

/// Details for the selected persona: name, home screen, sign-in method, duplicate, delete.
/// Create it with `ValueKey(persona.id)` so the form resets when the selection changes.
class PersonaSidePanel extends StatefulWidget {
  const PersonaSidePanel({
    super.key,
    required this.persona,
    required this.readOnly,
    required this.onSave,
    required this.onDuplicate,
    required this.onDelete,
  });

  final Persona persona;
  final bool readOnly;

  /// Receives the PATCH body: name, description, homeRoute, loginMethod.
  final ValueChanged<Map<String, dynamic>> onSave;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  State<PersonaSidePanel> createState() => _PersonaSidePanelState();
}

class _PersonaSidePanelState extends State<PersonaSidePanel> {
  late final TextEditingController _name = TextEditingController(text: widget.persona.name);
  late final TextEditingController _description =
      TextEditingController(text: widget.persona.description ?? '');
  late String _homeRoute = widget.persona.homeRoute;
  late LoginMethod _loginMethod = widget.persona.loginMethod;
  String? _nameError;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Enter a name');
      return;
    }
    setState(() => _nameError = null);
    final description = _description.text.trim();
    widget.onSave({
      'name': name,
      'description': description.isEmpty ? null : description,
      'homeRoute': _homeRoute,
      'loginMethod': loginMethodToApi(_loginMethod),
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final persona = widget.persona;
    final editable = !widget.readOnly && !persona.isSystem;
    final canDelete = editable && persona.userCount == 0;
    final textTheme = Theme.of(context).textTheme;
    final gap = SizedBox(height: t.spacing.md);

    return AppCard(
      title: 'Persona details',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (persona.isSystem)
            Padding(
              padding: EdgeInsets.only(bottom: t.spacing.md),
              child: Text(
                "The Admin persona is built in. It can't be edited or deleted.",
                style: textTheme.bodySmall,
              ),
            )
          else if (widget.readOnly)
            Padding(
              padding: EdgeInsets.only(bottom: t.spacing.md),
              child: Text('View only. Ask an admin to change this persona.', style: textTheme.bodySmall),
            ),
          if (editable) ...[
            AppTextField(label: 'Name', controller: _name, errorText: _nameError),
            gap,
            AppTextField(label: 'Description', controller: _description),
            gap,
            AppSelect<String>(
              label: 'Home screen',
              value: _homeRoute,
              items: [
                for (final route in {...homeRouteOptions, _homeRoute})
                  AppSelectItem(route, homeRouteLabel(route)),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _homeRoute = v);
              },
            ),
            gap,
            AppSelect<LoginMethod>(
              label: 'Sign in with',
              value: _loginMethod,
              items: [
                AppSelectItem(LoginMethod.password, loginMethodLabel(LoginMethod.password)),
                AppSelectItem(LoginMethod.pin, loginMethodLabel(LoginMethod.pin)),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _loginMethod = v);
              },
            ),
            gap,
            AppButton(label: 'Save details', variant: AppButtonVariant.primary, onPressed: _save),
          ] else ...[
            _ReadOnlyLine(label: 'Name', value: persona.name),
            _ReadOnlyLine(label: 'Description', value: persona.description ?? '—'),
            _ReadOnlyLine(label: 'Home screen', value: homeRouteLabel(persona.homeRoute)),
            _ReadOnlyLine(label: 'Sign in with', value: loginMethodLabel(persona.loginMethod)),
          ],
          if (!widget.readOnly) ...[
            gap,
            AppButton(
              label: 'Duplicate persona',
              icon: Icons.copy_outlined,
              onPressed: widget.onDuplicate,
            ),
          ],
          if (editable) ...[
            gap,
            AppButton(
              label: 'Delete persona',
              icon: Icons.delete_outline,
              variant: AppButtonVariant.danger,
              onPressed: canDelete ? widget.onDelete : null,
            ),
            if (!canDelete) ...[
              SizedBox(height: t.spacing.sm),
              Text(
                persona.userCount > 0
                    ? '${persona.userCount} ${persona.userCount == 1 ? 'user is' : 'users are'} on this persona. Move them before deleting.'
                    : 'Delete is not available.',
                style: textTheme.bodySmall,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ReadOnlyLine extends StatelessWidget {
  const _ReadOnlyLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: t.spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: textTheme.labelSmall),
          Text(value, style: textTheme.bodyMedium),
        ],
      ),
    );
  }
}
