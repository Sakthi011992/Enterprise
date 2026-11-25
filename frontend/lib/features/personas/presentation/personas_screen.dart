import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_billing/core/auth/permission_keys.dart';
import 'package:pos_billing/core/auth/permissions.dart';
import 'package:pos_billing/core/auth/session.dart';
import 'package:pos_billing/core/theme/app_theme.dart';
import 'package:pos_billing/core/ui/ui.dart';

import '../data/admin_api.dart';
import '../data/persona_models.dart';
import '../data/personas_repository.dart';
import 'permission_cell_editor.dart';
import 'persona_changes_bar.dart';
import 'persona_matrix.dart';
import 'persona_name_dialog.dart';
import 'persona_side_panel.dart';

/// Settings > Personas & permissions. Read-only unless the viewer has admin.users EDIT.
class PersonasScreen extends ConsumerStatefulWidget {
  const PersonasScreen({super.key});

  @override
  ConsumerState<PersonasScreen> createState() => _PersonasScreenState();
}

class _PersonasScreenState extends ConsumerState<PersonasScreen> {
  /// The last server data the draft was built from. Identity changes after each reload.
  PersonaMatrixData? _source;

  /// Unsaved edits: personaId -> key -> grant.
  Map<String, Map<String, PersonaGrant>> _draft = {};
  String? _selectedId;
  bool _saving = false;
  String? _error;

  void _resetDraft(PersonaMatrixData data) {
    _draft = {for (final e in data.grants.entries) e.key: Map.of(e.value)};
  }

  /// Rebuilds the draft when fresh server data arrives (first load, refresh, after save).
  void _syncFrom(PersonaMatrixData data) {
    if (identical(_source, data)) return;
    _source = data;
    _resetDraft(data);
    final stillThere = data.personas.any((p) => p.id == _selectedId);
    if (!stillThere) _selectedId = data.personas.isEmpty ? null : data.personas.first.id;
  }

  bool _isChanged(PersonaMatrixData data, String personaId, String key) {
    final original = grantFor(data.grants, personaId, key);
    final current = grantFor(_draft, personaId, key);
    return !original.sameAs(current);
  }

  List<String> _changedPersonaIds(PersonaMatrixData data) {
    final ids = <String>[];
    for (final persona in data.personas) {
      if (data.catalog.any((c) => _isChanged(data, persona.id, c.key))) ids.add(persona.id);
    }
    return ids;
  }

  int _changeCount(PersonaMatrixData data) {
    var count = 0;
    for (final persona in data.personas) {
      for (final entry in data.catalog) {
        if (_isChanged(data, persona.id, entry.key)) count++;
      }
    }
    return count;
  }

  int _affectedUsers(PersonaMatrixData data) {
    var users = 0;
    for (final id in _changedPersonaIds(data)) {
      for (final persona in data.personas) {
        if (persona.id == id) users += persona.userCount;
      }
    }
    return users;
  }

  bool get _hasUnsavedChanges {
    final source = _source;
    return source != null && _changeCount(source) > 0;
  }

  Persona? _findPersona(PersonaMatrixData data) {
    for (final persona in data.personas) {
      if (persona.id == _selectedId) return persona;
    }
    return null;
  }

  Future<void> _editCell(PersonaMatrixData data, CatalogEntry entry, Persona persona) async {
    final current = grantFor(_draft, persona.id, entry.key);
    final next = await showPermissionCellEditor(context, entry: entry, current: current);
    if (next == null || !mounted) return;
    setState(() => _draft.putIfAbsent(persona.id, () => {})[entry.key] = next);
  }

  Future<void> _saveChanges(PersonaMatrixData data) async {
    final repo = ref.read(personasRepositoryProvider);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      for (final personaId in _changedPersonaIds(data)) {
        final items = [for (final entry in data.catalog) grantFor(_draft, personaId, entry.key)];
        await repo.savePermissions(personaId, items);
      }
      ref.invalidate(personaMatrixProvider);
      if (mounted) showAppToast(context, 'Permissions saved');
    } catch (e) {
      // Keep the draft and skip the reload, so nothing the person typed is lost.
      if (mounted) setState(() => _error = AdminApiError.from(e).friendly);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Runs a persona write, then reloads. Blocks writes while matrix edits are unsaved.
  Future<void> _write(Future<void> Function() action, {String? success}) async {
    if (_hasUnsavedChanges) {
      setState(() => _error = 'Save or cancel your permission changes first.');
      return;
    }
    setState(() => _error = null);
    try {
      await action();
      ref.invalidate(personaMatrixProvider);
      if (mounted && success != null) showAppToast(context, success);
    } catch (e) {
      if (mounted) setState(() => _error = AdminApiError.from(e).friendly);
    }
  }

  Future<void> _createPersona() async {
    final name = await showPersonaNameDialog(context, title: 'New persona', confirmLabel: 'Create');
    if (name == null) return;
    await _write(() async {
      final created = await ref.read(personasRepositoryProvider).create(name: name);
      if (mounted) setState(() => _selectedId = created.id);
    }, success: 'Persona created');
  }

  Future<void> _duplicatePersona(Persona source) async {
    final name = await showPersonaNameDialog(
      context,
      title: 'Duplicate ${source.name}',
      confirmLabel: 'Duplicate',
      initial: '${source.name} copy',
    );
    if (name == null) return;
    await _write(() async {
      final created = await ref
          .read(personasRepositoryProvider)
          .create(name: name, copyFromId: source.id);
      if (mounted) setState(() => _selectedId = created.id);
    }, success: 'Persona duplicated');
  }

  Future<void> _savePersona(Persona persona, Map<String, dynamic> body) {
    return _write(() async {
      await ref.read(personasRepositoryProvider).update(persona.id, body);
    }, success: 'Persona saved');
  }

  Future<void> _deletePersona(Persona persona) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete ${persona.name}?',
      message: "Its permission settings are removed. This can't be undone.",
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    await _write(() async {
      await ref.read(personasRepositoryProvider).delete(persona.id);
      if (mounted) setState(() => _selectedId = null);
    }, success: 'Persona deleted');
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = can(ref, Perm.adminUsers, AccessLevel.edit);
    final matrix = ref.watch(personaMatrixProvider);
    final t = context.tokens;

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(t.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Personas & permissions',
              breadcrumb: 'Settings',
              actions: [
                if (canEdit)
                  AppButton(
                    label: 'New persona',
                    icon: Icons.add,
                    variant: AppButtonVariant.primary,
                    onPressed: _createPersona,
                  ),
              ],
            ),
            if (_error != null) ...[
              SizedBox(height: t.spacing.md),
              InlineAlert(message: _error!),
            ],
            SizedBox(height: t.spacing.md),
            Expanded(
              child: matrix.when(
                skipLoadingOnReload: true,
                loading: () => DelayedSkeleton(child: SkeletonList()),
                error: (e, _) => ErrorState(
                  message: AdminApiError.from(e).friendly,
                  onRetry: () => ref.invalidate(personaMatrixProvider),
                ),
                data: (data) {
                  _syncFrom(data);
                  return _buildLoaded(data, canEdit);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoaded(PersonaMatrixData data, bool canEdit) {
    final t = context.tokens;
    final selected = _findPersona(data);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: PersonaMatrix(
                  personas: data.personas,
                  catalog: data.catalog,
                  grantOf: (personaId, key) => grantFor(_draft, personaId, key),
                  isChanged: (personaId, key) => _isChanged(data, personaId, key),
                  selectedId: _selectedId,
                  readOnly: !canEdit,
                  onSelectPersona: (id) => setState(() => _selectedId = id),
                  onEditCell: (entry, persona) => _editCell(data, entry, persona),
                ),
              ),
              if (selected != null) ...[
                SizedBox(width: t.spacing.md),
                SizedBox(
                  width: 320,
                  child: SingleChildScrollView(
                    child: PersonaSidePanel(
                      key: ValueKey(selected.id),
                      persona: selected,
                      readOnly: !canEdit,
                      onSave: (body) => _savePersona(selected, body),
                      onDuplicate: () => _duplicatePersona(selected),
                      onDelete: () => _deletePersona(selected),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        PersonaChangesBar(
          changeCount: _changeCount(data),
          affectedUsers: _affectedUsers(data),
          readOnly: !canEdit,
          saving: _saving,
          onCancel: () => setState(() {
            _resetDraft(data);
            _error = null;
          }),
          onSave: () => _saveChanges(data),
        ),
      ],
    );
  }
}
