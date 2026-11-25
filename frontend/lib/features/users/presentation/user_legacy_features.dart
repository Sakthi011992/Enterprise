import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_billing/core/features/app_feature.dart';
import 'package:pos_billing/core/theme/app_theme.dart';
import 'package:pos_billing/core/ui/ui.dart';
import 'package:pos_billing/features/personas/data/admin_api.dart';

import '../data/users_repository.dart';

/// Per-user feature grants from before personas, kept under "Advanced (legacy)".
/// Persona permissions decide access. These grants only add extra screens for this user.
class UserLegacyFeatures extends ConsumerStatefulWidget {
  const UserLegacyFeatures({super.key, required this.userId, required this.readOnly});

  final String userId;
  final bool readOnly;

  @override
  ConsumerState<UserLegacyFeatures> createState() => _UserLegacyFeaturesState();
}

class _UserLegacyFeaturesState extends ConsumerState<UserLegacyFeatures> {
  static const _labels = {
    AppFeature.dashboard: ('Dashboard', Icons.dashboard),
    AppFeature.products: ('Products', Icons.inventory_2),
    AppFeature.tax: ('Tax Settings', Icons.percent),
    AppFeature.users: ('User Management', Icons.people),
    AppFeature.orders: ('Orders', Icons.receipt_long),
    AppFeature.appearance: ('Appearance / Themes', Icons.palette),
  };

  /// Working copy of the grants. Null until the server answers.
  Set<AppFeature>? _granted;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    final granted = _granted;
    if (granted == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(usersRepositoryProvider).setFeatures(widget.userId, granted);
      ref.invalidate(userFeaturesProvider(widget.userId));
      if (mounted) showAppToast(context, 'Feature grants saved');
    } catch (e) {
      if (mounted) setState(() => _error = AdminApiError.from(e).friendly);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final loaded = ref.watch(userFeaturesProvider(widget.userId));

    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('Advanced (legacy)'),
      subtitle: const Text('Extra screens from before personas'),
      childrenPadding: EdgeInsets.only(bottom: t.spacing.md),
      children: [
        Text(
          'Persona permissions decide what this user can do. These grants only add '
          'extra screens for this user. They will be removed in Phase 2.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        SizedBox(height: t.spacing.sm),
        if (_error != null) ...[
          InlineAlert(message: _error!),
          SizedBox(height: t.spacing.sm),
        ],
        loaded.when(
          loading: () => DelayedSkeleton(child: const SkeletonList(rows: 3)),
          error: (e, _) => ErrorState(
            message: AdminApiError.from(e).friendly,
            onRetry: () => ref.invalidate(userFeaturesProvider(widget.userId)),
          ),
          data: (serverSet) {
            _granted ??= {...serverSet};
            final granted = _granted!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final feature in AppFeature.userGrantable)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(_labels[feature]!.$2),
                    title: Text(_labels[feature]!.$1),
                    value: granted.contains(feature),
                    onChanged: widget.readOnly || _saving
                        ? null
                        : (v) => setState(() {
                              if (v == true) {
                                granted.add(feature);
                              } else {
                                granted.remove(feature);
                              }
                            }),
                  ),
                if (!widget.readOnly) ...[
                  SizedBox(height: t.spacing.sm),
                  AppButton(
                    label: _saving ? 'Saving…' : 'Save feature grants',
                    loading: _saving,
                    onPressed: _saving ? null : _save,
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}
