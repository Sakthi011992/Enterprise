// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/app_config.dart';
import '../../../core/files/pick_file.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/token_ext.dart';
import '../../../core/theme/theme_mode_toggle.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final _themesListProvider = FutureProvider<List<Map>>((ref) async {
  final res = await ref.watch(dioProvider).get('/themes');
  final raw = res.data;
  if (raw is List) return raw.cast<Map>();
  if (raw is Map && raw['data'] is List) return (raw['data'] as List).cast<Map>();
  return [];
});

final _logosProvider = FutureProvider.family<List<Map>, String>((ref, themeId) async {
  final res = await ref.watch(dioProvider).get('/branding/$themeId/logos');
  return (res.data as List).cast<Map>();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class BrandingScreen extends ConsumerStatefulWidget {
  const BrandingScreen({super.key});
  @override
  ConsumerState<BrandingScreen> createState() => _BrandingScreenState();
}

class _BrandingScreenState extends ConsumerState<BrandingScreen> {
  String? _selectedThemeId;

  @override
  Widget build(BuildContext context) {
    final themes = ref.watch(_themesListProvider);
    final t = context.tokens;
    return Scaffold(
      appBar: AppBar(title: const Text('Branding & Logos'), actions: const [ThemeModeToggle()]),
      body: themes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (themeList) {
          if (themeList.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.palette_outlined, size: 56, color: t.color.content.muted),
                const SizedBox(height: 16),
                const Text('No themes yet. Create a theme in Appearance first.'),
              ]),
            );
          }
          _selectedThemeId ??= themeList.first['id'] as String;
          return Row(
            children: [
              // Theme picker sidebar
              SizedBox(
                width: 200,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.all(t.spacing.md),
                      child: Text('Themes', style: Theme.of(context).textTheme.labelLarge),
                    ),
                    Expanded(
                      child: ListView(
                        children: themeList.map((th) {
                          final id = th['id'] as String;
                          final name = th['name'] as String? ?? id;
                          return ListTile(
                            title: Text(name),
                            selected: id == _selectedThemeId,
                            onTap: () => setState(() => _selectedThemeId = id),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              // Logo grid for selected theme
              if (_selectedThemeId != null)
                Expanded(child: _LogoGrid(themeId: _selectedThemeId!)),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Logo grid for one theme
// ---------------------------------------------------------------------------

const _roles = ['WORDMARK', 'ICON'];
const _variants = ['LIGHT', 'DARK'];

class _LogoGrid extends ConsumerWidget {
  const _LogoGrid({required this.themeId});
  final String themeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logos = ref.watch(_logosProvider(themeId));
    final t = context.tokens;
    return logos.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (logoList) {
        Map<String, Map?> logoMap = {};
        for (final l in logoList) {
          final key = '${l['role']}_${l['variant']}';
          logoMap[key] = l;
        }
        return SingleChildScrollView(
          padding: EdgeInsets.all(t.spacing.lg),
          child: Wrap(
            spacing: t.spacing.md,
            runSpacing: t.spacing.md,
            children: [
              for (final role in _roles)
                for (final variant in _variants)
                  _LogoCard(
                    themeId: themeId,
                    role: role,
                    variant: variant,
                    logo: logoMap['${role}_$variant'],
                    onUploaded: () => ref.invalidate(_logosProvider(themeId)),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _LogoCard extends ConsumerStatefulWidget {
  const _LogoCard({
    required this.themeId,
    required this.role,
    required this.variant,
    required this.logo,
    required this.onUploaded,
  });
  final String themeId;
  final String role;
  final String variant;
  final Map? logo;
  final VoidCallback onUploaded;
  @override
  ConsumerState<_LogoCard> createState() => _LogoCardState();
}

class _LogoCardState extends ConsumerState<_LogoCard> {
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    final file = await pickImageFile(allowedExtensions: const ['png', 'svg', 'jpg', 'jpeg']);
    if (file == null) return;
    await _upload(file.bytes, file.name, file.mimeType);
  }

  Future<void> _upload(Uint8List bytes, String filename, String mimeType) async {
    setState(() => _uploading = true);
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: filename,
          contentType: DioMediaType.parse(mimeType.isNotEmpty ? mimeType : 'image/png'),
        ),
      });
      await ref.read(dioProvider).post(
        '/branding/${widget.themeId}/logo',
        data: formData,
        queryParameters: {'role': widget.role, 'variant': widget.variant},
      );
      widget.onUploaded();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final logo = widget.logo;
    final hasLogo = logo != null;
    final isDark = widget.variant == 'DARK';
    final previewBg = isDark ? t.color.background.inverse : context.ext.subtleFill;
    final blobPath = logo?['blobPath'] as String?;

    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(t.spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    widget.role == 'WORDMARK' ? Icons.text_fields : Icons.crop_square,
                    size: 16,
                    color: t.color.content.secondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${widget.role} · ${widget.variant}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: t.color.content.secondary),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                height: 100,
                decoration: BoxDecoration(
                  color: previewBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: t.color.content.muted.withValues(alpha: 0.2)),
                ),
                alignment: Alignment.center,
                child: hasLogo && blobPath != null
                    ? Image.network(
                        '${AppConfig.apiBaseUrl}/branding/serve/$blobPath',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(Icons.broken_image, color: t.color.content.muted),
                      )
                    : Icon(Icons.image_outlined, size: 40, color: t.color.content.muted),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: _uploading
                    ? const LinearProgressIndicator()
                    : OutlinedButton.icon(
                        icon: const Icon(Icons.upload, size: 16),
                        label: Text(hasLogo ? 'Replace' : 'Upload'),
                        onPressed: _pickAndUpload,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
