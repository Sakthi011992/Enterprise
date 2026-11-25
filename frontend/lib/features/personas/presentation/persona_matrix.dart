import 'package:flutter/material.dart';
import 'package:pos_billing/core/auth/session.dart';
import 'package:pos_billing/core/theme/app_theme.dart';
import 'package:pos_billing/core/ui/ui.dart';

import '../data/persona_models.dart';

const double _labelColumnWidth = 260;
const double _personaColumnWidth = 156;
const double _rowHeight = 52;
const double _headerHeight = 64;

/// Permission x persona grid. Rows are grouped by catalog group; one column per persona.
/// Scrolls both ways so a wide matrix stays usable on a tablet.
class PersonaMatrix extends StatelessWidget {
  const PersonaMatrix({
    super.key,
    required this.personas,
    required this.catalog,
    required this.grantOf,
    required this.isChanged,
    required this.selectedId,
    required this.readOnly,
    required this.onSelectPersona,
    required this.onEditCell,
  });

  final List<Persona> personas;
  final List<CatalogEntry> catalog;
  final PersonaGrant Function(String personaId, String key) grantOf;
  final bool Function(String personaId, String key) isChanged;
  final String? selectedId;
  final bool readOnly;
  final ValueChanged<String> onSelectPersona;
  final void Function(CatalogEntry entry, Persona persona) onEditCell;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      _HeaderRow(personas: personas, selectedId: selectedId, onSelect: onSelectPersona),
    ];
    for (final group in groupCatalog(catalog)) {
      rows.add(_GroupRow(label: group.key));
      for (final entry in group.value) {
        rows.add(_PermissionRow(
          entry: entry,
          personas: personas,
          grantOf: grantOf,
          isChanged: isChanged,
          readOnly: readOnly,
          onEditCell: onEditCell,
        ));
      }
    }
    final width = _labelColumnWidth + _personaColumnWidth * personas.length;
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
        ),
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.personas, required this.selectedId, required this.onSelect});

  final List<Persona> personas;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Container(
          width: _labelColumnWidth,
          height: _headerHeight,
          alignment: Alignment.centerLeft,
          padding: EdgeInsets.symmetric(horizontal: t.spacing.sm),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.color.border.strong, width: t.borderWidth.hairline)),
          ),
          child: Text('Permission', style: Theme.of(context).textTheme.labelMedium),
        ),
        for (final persona in personas)
          _PersonaHeaderCell(
            persona: persona,
            selected: persona.id == selectedId,
            onTap: () => onSelect(persona.id),
          ),
      ],
    );
  }
}

class _PersonaHeaderCell extends StatelessWidget {
  const _PersonaHeaderCell({required this.persona, required this.selected, required this.onTap});

  final Persona persona;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    final users = persona.userCount == 1 ? 'user' : 'users';
    return InkWell(
      onTap: onTap,
      child: Container(
        width: _personaColumnWidth,
        height: _headerHeight,
        padding: EdgeInsets.symmetric(horizontal: t.spacing.sm),
        decoration: BoxDecoration(
          color: selected ? t.color.background.raised : null,
          border: Border(
            bottom: BorderSide(
              color: selected ? t.color.border.accent : t.color.border.strong,
              width: selected ? t.borderWidth.thick : t.borderWidth.hairline,
            ),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(persona.name,
                      overflow: TextOverflow.ellipsis, style: textTheme.titleMedium),
                ),
                if (persona.isSystem) ...[
                  SizedBox(width: t.spacing.xs),
                  Tooltip(
                    message: 'Built-in. Read-only.',
                    child: Icon(Icons.lock_outline, size: 14, color: t.color.content.muted),
                  ),
                ],
              ],
            ),
            Text('${persona.userCount} $users', style: textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: 36,
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.symmetric(horizontal: t.spacing.sm),
      color: t.color.background.surface,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: t.color.content.muted),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.entry,
    required this.personas,
    required this.grantOf,
    required this.isChanged,
    required this.readOnly,
    required this.onEditCell,
  });

  final CatalogEntry entry;
  final List<Persona> personas;
  final PersonaGrant Function(String personaId, String key) grantOf;
  final bool Function(String personaId, String key) isChanged;
  final bool readOnly;
  final void Function(CatalogEntry entry, Persona persona) onEditCell;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final label = Text(entry.label, style: Theme.of(context).textTheme.bodyMedium);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.color.border.subtle, width: t.borderWidth.hairline)),
      ),
      child: Row(
        children: [
          Container(
            width: _labelColumnWidth,
            height: _rowHeight,
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.symmetric(horizontal: t.spacing.sm),
            child: entry.description == null
                ? label
                : Tooltip(message: entry.description!, child: label),
          ),
          for (final persona in personas)
            _PermissionCell(
              persona: persona,
              entry: entry,
              grant: grantOf(persona.id, entry.key),
              changed: isChanged(persona.id, entry.key),
              editable: !readOnly && !persona.isSystem,
              onTap: () => onEditCell(entry, persona),
            ),
        ],
      ),
    );
  }
}

class _PermissionCell extends StatelessWidget {
  const _PermissionCell({
    required this.persona,
    required this.entry,
    required this.grant,
    required this.changed,
    required this.editable,
    required this.onTap,
  });

  final Persona persona;
  final CatalogEntry entry;
  final PersonaGrant grant;
  final bool changed;
  final bool editable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ext = context.ext;
    final (Color background, Color foreground) = switch (grant.level) {
      AccessLevel.edit || AccessLevel.approve => (ext.successSubtle, ext.onSuccessSubtle),
      AccessLevel.view => (ext.neutralSubtle, ext.onNeutralSubtle),
      AccessLevel.request || AccessLevel.limited => (ext.warningSubtle, ext.onWarningSubtle),
      AccessLevel.none => (t.color.background.surface, t.color.content.muted),
    };
    final label = permissionLabel(grant, entry);
    return SizedBox(
      width: _personaColumnWidth,
      height: _rowHeight,
      child: Center(
        child: Semantics(
          button: editable,
          label: '${entry.label} for ${persona.name}: $label',
          child: InkWell(
            borderRadius: BorderRadius.circular(t.radius.pill),
            onTap: editable ? onTap : null,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: t.spacing.sm, vertical: t.spacing.xs),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(t.radius.pill),
                border: Border.all(
                  color: changed ? t.color.border.accent : background,
                  width: changed ? t.borderWidth.thick : t.borderWidth.none,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (changed) ...[
                    Icon(Icons.edit_outlined, size: 12, color: foreground),
                    SizedBox(width: t.spacing.xs),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: foreground),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
